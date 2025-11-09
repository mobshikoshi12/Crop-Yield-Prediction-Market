(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-already-exists (err u102))
(define-constant err-market-closed (err u103))
(define-constant err-insufficient-funds (err u104))
(define-constant err-unauthorized (err u105))
(define-constant err-market-resolved (err u106))
(define-constant err-invalid-amount (err u107))

(define-data-var market-counter uint u0)
(define-data-var oracle-address (optional principal) none)

(define-map markets uint {
    creator: principal,
    crop-type: (string-ascii 50),
    region: (string-ascii 100),
    target-yield: uint,
    deadline: uint,
    total-higher: uint,
    total-lower: uint,
    resolved: bool,
    actual-yield: (optional uint),
    resolution-block: (optional uint)
})

(define-map user-bets {user: principal, market-id: uint} {
    amount: uint,
    bet-higher: bool,
    claimed: bool
})

(define-map oracles principal bool)

(define-public (set-oracle (oracle principal))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (var-set oracle-address (some oracle))
        (map-set oracles oracle true)
        (ok true)))

(define-public (create-market (crop-type (string-ascii 50)) (region (string-ascii 100)) (target-yield uint) (deadline uint))
    (let ((market-id (+ (var-get market-counter) u1)))
        (asserts! (> deadline stacks-block-height) err-market-closed)
        (asserts! (> target-yield u0) err-invalid-amount)
        (map-set markets market-id {
            creator: tx-sender,
            crop-type: crop-type,
            region: region,
            target-yield: target-yield,
            deadline: deadline,
            total-higher: u0,
            total-lower: u0,
            resolved: false,
            actual-yield: none,
            resolution-block: none
        })
        (var-set market-counter market-id)
        (ok market-id)))

(define-public (place-bet (market-id uint) (amount uint) (bet-higher bool))
    (let ((market (unwrap! (map-get? markets market-id) err-not-found))
          (existing-bet (map-get? user-bets {user: tx-sender, market-id: market-id})))
        (asserts! (> amount u0) err-invalid-amount)
        (asserts! (< stacks-block-height (get deadline market)) err-market-closed)
        (asserts! (not (get resolved market)) err-market-resolved)
        (asserts! (is-none existing-bet) err-already-exists)
        (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
        (map-set user-bets {user: tx-sender, market-id: market-id} {
            amount: amount,
            bet-higher: bet-higher,
            claimed: false
        })
        (if bet-higher
            (map-set markets market-id (merge market {total-higher: (+ (get total-higher market) amount)}))
            (map-set markets market-id (merge market {total-lower: (+ (get total-lower market) amount)})))
        (ok true)))

(define-public (resolve-market (market-id uint) (actual-yield uint))
    (let ((market (unwrap! (map-get? markets market-id) err-not-found)))
        (asserts! (default-to false (map-get? oracles tx-sender)) err-unauthorized)
        (asserts! (>= stacks-block-height (get deadline market)) err-market-closed)
        (asserts! (not (get resolved market)) err-market-resolved)
        (asserts! (> actual-yield u0) err-invalid-amount)
        (map-set markets market-id (merge market {
            resolved: true,
            actual-yield: (some actual-yield),
            resolution-block: (some stacks-block-height)
        }))
        (ok true)))

(define-public (claim-winnings (market-id uint))
    (let ((market (unwrap! (map-get? markets market-id) err-not-found))
          (user-bet (unwrap! (map-get? user-bets {user: tx-sender, market-id: market-id}) err-not-found))
          (actual-yield (unwrap! (get actual-yield market) err-market-resolved))
          (target-yield (get target-yield market)))
        (asserts! (get resolved market) err-market-resolved)
        (asserts! (not (get claimed user-bet)) err-already-exists)
        (let ((user-won (if (get bet-higher user-bet)
                           (>= actual-yield target-yield)
                           (< actual-yield target-yield)))
              (total-winning-pool (if (>= actual-yield target-yield)
                                    (get total-higher market)
                                    (get total-lower market)))
              (total-losing-pool (if (>= actual-yield target-yield)
                                   (get total-lower market)
                                   (get total-higher market))))
            (asserts! user-won err-unauthorized)
            (map-set user-bets {user: tx-sender, market-id: market-id} (merge user-bet {claimed: true}))
            (if (> total-winning-pool u0)
                (let ((payout (+ (get amount user-bet) 
                               (/ (* (get amount user-bet) total-losing-pool) total-winning-pool))))
                    (as-contract (stx-transfer? payout tx-sender tx-sender)))
                (as-contract (stx-transfer? (get amount user-bet) tx-sender tx-sender))))))

(define-read-only (get-market (market-id uint))
    (map-get? markets market-id))

(define-read-only (get-user-bet (user principal) (market-id uint))
    (map-get? user-bets {user: user, market-id: market-id}))

(define-read-only (get-market-count)
    (var-get market-counter))

(define-read-only (get-oracle)
    (var-get oracle-address))

(define-read-only (is-oracle (user principal))
    (default-to false (map-get? oracles user)))

(define-read-only (calculate-potential-payout (market-id uint) (amount uint) (bet-higher bool))
    (match (map-get? markets market-id)
        market (let ((total-opposite (if bet-higher (get total-lower market) (get total-higher market)))
                     (total-same (if bet-higher (get total-higher market) (get total-lower market))))
                  (if (> (+ total-same amount) u0)
                      (ok (+ amount (/ (* amount total-opposite) (+ total-same amount))))
                      (ok amount)))
        err-not-found))

(define-read-only (get-market-stats (market-id uint))
    (match (map-get? markets market-id)
        market (ok {
            total-volume: (+ (get total-higher market) (get total-lower market)),
            higher-percentage: (if (> (+ (get total-higher market) (get total-lower market)) u0)
                                 (/ (* (get total-higher market) u100) 
                                    (+ (get total-higher market) (get total-lower market)))
                                 u50),
            lower-percentage: (if (> (+ (get total-higher market) (get total-lower market)) u0)
                                (/ (* (get total-lower market) u100) 
                                   (+ (get total-higher market) (get total-lower market)))
                                u50)
        })
        err-not-found))


(define-map user-activity principal {
    markets-created: uint,
    total-bets: uint,
    winnings-claimed: uint,
    total-volume: uint,
    reputation-score: uint
})

(define-map market-accuracy uint {
    creator: principal,
    resolved: bool,
    participants: uint,
    total-volume: uint
})

(define-public (track-market-creation (market-id uint))
    (let ((current-stats (default-to {markets-created: u0, total-bets: u0, winnings-claimed: u0, total-volume: u0, reputation-score: u0}
                                   (map-get? user-activity tx-sender))))
        (map-set user-activity tx-sender 
            (merge current-stats {
                markets-created: (+ (get markets-created current-stats) u1),
                reputation-score: (+ (get reputation-score current-stats) u10)
            }))
        (map-set market-accuracy market-id {
            creator: tx-sender,
            resolved: false,
            participants: u0,
            total-volume: u0
        })
        (ok true)))

(define-public (track-bet-placement (market-id uint) (amount uint))
    (let ((current-stats (default-to {markets-created: u0, total-bets: u0, winnings-claimed: u0, total-volume: u0, reputation-score: u0}
                                   (map-get? user-activity tx-sender)))
          (market-data (default-to {creator: tx-sender, resolved: false, participants: u0, total-volume: u0}
                                  (map-get? market-accuracy market-id))))
        (map-set user-activity tx-sender
            (merge current-stats {
                total-bets: (+ (get total-bets current-stats) u1),
                total-volume: (+ (get total-volume current-stats) amount),
                reputation-score: (+ (get reputation-score current-stats) u5)
            }))
        (map-set market-accuracy market-id
            (merge market-data {
                participants: (+ (get participants market-data) u1),
                total-volume: (+ (get total-volume market-data) amount)
            }))
        (ok true)))

(define-public (track-winnings-claimed (market-id uint) (payout uint))
    (let ((current-stats (default-to {markets-created: u0, total-bets: u0, winnings-claimed: u0, total-volume: u0, reputation-score: u0}
                                   (map-get? user-activity tx-sender))))
        (map-set user-activity tx-sender
            (merge current-stats {
                winnings-claimed: (+ (get winnings-claimed current-stats) u1),
                reputation-score: (+ (get reputation-score current-stats) u15)
            }))
        (ok true)))

(define-public (update-market-resolution (market-id uint))
    (let ((market-data (unwrap! (map-get? market-accuracy market-id) err-not-found)))
        (map-set market-accuracy market-id
            (merge market-data {resolved: true}))
        (let ((creator-stats (default-to {markets-created: u0, total-bets: u0, winnings-claimed: u0, total-volume: u0, reputation-score: u0}
                                        (map-get? user-activity (get creator market-data))))
              (bonus-score (if (> (get participants market-data) u5) u25 u10)))
            (map-set user-activity (get creator market-data)
                (merge creator-stats {
                    reputation-score: (+ (get reputation-score creator-stats) bonus-score)
                })))
        (ok true)))

(define-read-only (get-user-activity (user principal))
    (default-to {markets-created: u0, total-bets: u0, winnings-claimed: u0, total-volume: u0, reputation-score: u0}
               (map-get? user-activity user)))

(define-read-only (get-market-performance (market-id uint))
    (map-get? market-accuracy market-id))

(define-read-only (calculate-user-ranking (user principal))
    (let ((stats (get-user-activity user)))
        (ok {
            total-activity: (+ (+ (get markets-created stats) (get total-bets stats)) (get winnings-claimed stats)),
            reputation-score: (get reputation-score stats),
            success-rate: (if (> (get total-bets stats) u0)
                             (/ (* (get winnings-claimed stats) u100) (get total-bets stats))
                             u0)
        })))