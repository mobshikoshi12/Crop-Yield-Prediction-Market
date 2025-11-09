(define-constant err-not-found (err u401))
(define-constant err-insufficient-balance (err u402))
(define-constant err-invalid-amount (err u403))
(define-constant err-no-points (err u404))
(define-constant err-pool-empty (err u405))

(define-data-var rewards-pool-balance uint u0)
(define-data-var total-points-issued uint u0)
(define-data-var points-per-stx uint u100)
(define-data-var balance-threshold uint u60)

(define-map user-reward-points principal uint)

(define-map market-liquidity-state uint {
    first-bet-claimed: bool,
    total-bets: uint
})

(define-public (fund-rewards-pool (amount uint))
    (begin
        (asserts! (> amount u0) err-invalid-amount)
        (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
        (var-set rewards-pool-balance (+ (var-get rewards-pool-balance) amount))
        (ok true)))

(define-public (earn-liquidity-points (market-id uint) (bet-amount uint) (bet-higher bool) (total-higher uint) (total-lower uint))
    (let (
        (market-state (default-to {first-bet-claimed: false, total-bets: u0}
                                 (map-get? market-liquidity-state market-id)))
        (total-pool (+ total-higher total-lower))
        (user-points (default-to u0 (map-get? user-reward-points tx-sender)))
        (base-points (/ bet-amount u100000))
    )
        (asserts! (> bet-amount u0) err-invalid-amount)
        (let (
            (first-bet-bonus (if (not (get first-bet-claimed market-state)) u50 u0))
            (balance-bonus (calculate-balance-bonus bet-higher total-higher total-lower total-pool))
            (total-earned-points (+ base-points (+ first-bet-bonus balance-bonus)))
        )
            (map-set user-reward-points tx-sender (+ user-points total-earned-points))
            (var-set total-points-issued (+ (var-get total-points-issued) total-earned-points))
            (map-set market-liquidity-state market-id {
                first-bet-claimed: true,
                total-bets: (+ (get total-bets market-state) u1)
            })
            (ok total-earned-points))))

(define-private (calculate-balance-bonus (bet-higher bool) (total-higher uint) (total-lower uint) (total-pool uint))
    (if (is-eq total-pool u0)
        u0
        (let (
            (side-pool (if bet-higher total-lower total-higher))
            (side-percentage (/ (* side-pool u100) total-pool))
        )
            (if (< side-percentage (var-get balance-threshold))
                u30
                u0))))

(define-public (redeem-points (points-to-redeem uint))
    (let (
        (user-points (default-to u0 (map-get? user-reward-points tx-sender)))
        (stx-amount (/ points-to-redeem (var-get points-per-stx)))
    )
        (asserts! (> points-to-redeem u0) err-invalid-amount)
        (asserts! (>= user-points points-to-redeem) err-no-points)
        (asserts! (>= (var-get rewards-pool-balance) stx-amount) err-pool-empty)
        (map-set user-reward-points tx-sender (- user-points points-to-redeem))
        (var-set rewards-pool-balance (- (var-get rewards-pool-balance) stx-amount))
        (as-contract (stx-transfer? stx-amount tx-sender tx-sender))))

(define-read-only (get-user-points (user principal))
    (default-to u0 (map-get? user-reward-points user)))

(define-read-only (get-rewards-pool-balance)
    (var-get rewards-pool-balance))

(define-read-only (estimate-points-value (points uint))
    (ok (/ points (var-get points-per-stx))))

(define-read-only (get-market-liquidity-stats (market-id uint))
    (map-get? market-liquidity-state market-id))
