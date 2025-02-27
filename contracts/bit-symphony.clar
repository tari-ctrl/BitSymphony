;; Title: BitSymphony - Automated Portfolio Orchestrator
;; 
;; Summary: 
;; A non-custodial portfolio management engine enabling self-sovereign asset allocation
;; with Bitcoin-finalized settlements on Stacks L2. Dynamically rebalances multi-asset
;; portfolios through trustless smart contracts.

;; Description:
;; BitSymphony implements a decentralized asset management protocol combining Bitcoin's 
;; security with Stacks Layer 2 scalability. Key innovations:
;;
;; - Programmable asset baskets with algorithmic rebalancing triggers
;; - Non-custodial structure preserving user sovereignty over assets
;; - Bitcoin-anchored settlement layer for allocation changes
;; - Fee-efficient swaps via integrated Stacks AMM routing
;; - Multi-sig compatible ownership models
;; - Compliance-ready percentage tracking with on-chain audit trails
;;
;; Designed for Bitcoin-native DeFi, this protocol enables institutional-grade portfolio
;; strategies executable through smart contracts while maintaining full compatibility
;; with Bitcoin's security model through Stacks L2 proof transfers.

;; Error Codes
(define-constant ERR-NOT-AUTHORIZED (err u100))      ;; Unauthorized principal
(define-constant ERR-INVALID-PORTFOLIO (err u101))   ;; Nonexistent/inactive portfolio
(define-constant ERR-INSUFFICIENT-BALANCE (err u102));; Insufficient token balance
(define-constant ERR-INVALID-TOKEN (err u103))      ;; Unsupported token contract
(define-constant ERR-REBALANCE-FAILED (err u104))   ;; Failed allocation adjustment
(define-constant ERR-PORTFOLIO-EXISTS (err u105))    ;; Duplicate portfolio ID
(define-constant ERR-INVALID-PERCENTAGE (err u106))  ;; Invalid basis points allocation
(define-constant ERR-MAX-TOKENS-EXCEEDED (err u107)) ;; Token limit per portfolio
(define-constant ERR-LENGTH-MISMATCH (err u108))    ;; Parameter array mismatch
(define-constant ERR-USER-STORAGE-FAILED (err u109)) ;; Failed user state update
(define-constant ERR-INVALID-TOKEN-ID (err u110))    ;; Nonexistent token position

;; Protocol Configuration (Stacks L2 Optimized)
(define-data-var protocol-owner principal tx-sender) ;; Multi-sig upgradable
(define-data-var portfolio-counter uint u0)          ;; Global portfolio ID counter
(define-data-var protocol-fee uint u25)              ;; 0.25% in basis points (2500 = 25bps)

;; Domain Constants
(define-constant MAX-TOKENS-PER-PORTFOLIO u10)       ;; Gas-optimized upper limit
(define-constant BASIS-POINTS u10000)                /// 100% = 10,000 basis points

;; Core Data Structures
(define-map Portfolios
    uint                                             ;; Unique portfolio ID
    {
        owner: principal,                           ;; Stacks wallet address
        created-at: uint,                            ;; Block height of creation
        last-rebalanced: uint,                       ;; Last adjustment block
        total-value: uint,                           ;; Aggregated value in USD*100
        active: bool,                                ;; Portfolio status flag
        token-count: uint                           ;; Current asset count
    }
)

(define-map PortfolioAssets
    {portfolio-id: uint, token-id: uint}            ;; Composite key
    {
        target-percentage: uint,                    ;; Basis points allocation
        current-amount: uint,                       ;; Scaled token quantity
        token-address: principal                    ;; SIP-010 compliant
    }
)

(define-map UserPortfolios
    principal                                       ;; Owner address
    (list 20 uint)                                  ;; Portfolio ID registry
)

;; Read-Only Functions

;; Retrieves portfolio details by ID
(define-read-only (get-portfolio (portfolio-id uint))
    (map-get? Portfolios portfolio-id)
)

;; Retrieves specific asset details within a portfolio
(define-read-only (get-portfolio-asset (portfolio-id uint) (token-id uint))
    (map-get? PortfolioAssets {portfolio-id: portfolio-id, token-id: token-id})
)

;; Returns list of portfolio IDs owned by a user
(define-read-only (get-user-portfolios (user principal))
    (default-to (list) (map-get? UserPortfolios user))
)

;; Calculates rebalancing requirements for a portfolio
(define-read-only (calculate-rebalance-amounts (portfolio-id uint))
    (let (
        (portfolio (unwrap! (get-portfolio portfolio-id) ERR-INVALID-PORTFOLIO))
        (total-value (get total-value portfolio))
    )
    (ok {
        portfolio-id: portfolio-id,
        total-value: total-value,
        needs-rebalance: (> (- block-height (get last-rebalanced portfolio)) u144)
    }))
)

;; Private Functions

;; Validates token ID within portfolio constraints
(define-private (validate-token-id (portfolio-id uint) (token-id uint))
    (let (
        (portfolio (unwrap! (get-portfolio portfolio-id) false))
    )
    (and 
        (< token-id MAX-TOKENS-PER-PORTFOLIO)
        (< token-id (get token-count portfolio))
        true
    ))
)

;; Validates percentage is within valid range (0-10000 basis points)
(define-private (validate-percentage (percentage uint))
    (and (>= percentage u0) (<= percentage BASIS-POINTS))
)

;; Validates sum of portfolio percentages
(define-private (validate-portfolio-percentages (percentages (list 10 uint)))
    (let (
        (total (fold + percentages u0))
    )
    (and 
        ;; Check if total equals 100% (10000 basis points)
        (is-eq total BASIS-POINTS)
        ;; Check if each percentage is valid
        (fold and 
            (map validate-percentage percentages)
            true)
    ))
)	

;; Helper function for percentage validation
(define-private (check-percentage-sum (current-percentage uint) (valid bool))
    (and valid (validate-percentage current-percentage))
)

;; Adds portfolio ID to user's portfolio list
(define-private (add-to-user-portfolios (user principal) (portfolio-id uint))
    (let (
        (current-portfolios (get-user-portfolios user))
        (new-portfolios (unwrap! (as-max-len? (append current-portfolios portfolio-id) u20) ERR-USER-STORAGE-FAILED))
    )
    (map-set UserPortfolios user new-portfolios)
    (ok true))
)