;; TimeAccess - Time-Based Access Control

;; Constants
(define-constant DEFAULT_PRICE u1000000) ;; 1 STX
(define-constant DEFAULT_DURATION u144) ;; approx. 1 day (in blocks)

;; Error constants
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_ACCESS_REVOKED (err u101))
(define-constant ERR_INSUFFICIENT_FUNDS (err u102))
(define-constant ERR_INVALID_DURATION (err u103))
(define-constant ERR_INVALID_PRICE (err u104))

;; Contract owner
(define-data-var contract-owner principal tx-sender)

;; Subscription data
(define-map subscriptions
  principal
  {expires-at: uint})

;; Contract settings
(define-data-var access-price uint DEFAULT_PRICE)
(define-data-var access-duration uint DEFAULT_DURATION)

;; Revenue tracking
(define-data-var total-revenue uint u0)

;; Helper functions
(define-private (is-contract-owner)
  (is-eq tx-sender (var-get contract-owner)))

;; Admin functions

;; Update contract settings (price and duration)
(define-public (update-settings (price uint) (duration uint))
  (begin
    (asserts! (is-contract-owner) ERR_UNAUTHORIZED)
    (asserts! (> price u0) ERR_INVALID_PRICE)
    (asserts! (> duration u0) ERR_INVALID_DURATION)
    (var-set access-price price)
    (var-set access-duration duration)
    (ok {price: price, duration: duration})))

;; Transfer contract ownership
(define-public (transfer-ownership (new-owner principal))
  (begin
    (asserts! (is-contract-owner) ERR_UNAUTHORIZED)
    (asserts! (not (is-eq new-owner tx-sender)) ERR_INVALID_PRICE)
    (var-set contract-owner new-owner)
    (ok new-owner)))

;; Withdraw contract revenue
(define-public (withdraw-revenue (amount uint))
  (let (
    (contract-balance (stx-get-balance (as-contract tx-sender))))
    (begin
      (asserts! (is-contract-owner) ERR_UNAUTHORIZED)
      (asserts! (<= amount contract-balance) ERR_INSUFFICIENT_FUNDS)
      (try! (as-contract (stx-transfer? amount tx-sender (var-get contract-owner))))
      (ok amount))))

;; Revoke user access (for abuse cases)
(define-public (revoke-access (user principal))
  (begin
    (asserts! (is-contract-owner) ERR_UNAUTHORIZED)
    (asserts! (not (is-eq user tx-sender)) ERR_INVALID_PRICE)
    (map-set subscriptions user {expires-at: u0})
    (ok true)))

;; Grant free access (admin function)
(define-public (grant-access (user principal) (blocks uint))
  (let (
    (current-sub (default-to {expires-at: u0} (map-get? subscriptions user)))
    (current-expiry (get expires-at current-sub))
    (new-expiry (+ (if (> stacks-block-height current-expiry) stacks-block-height current-expiry) blocks)))
    (begin
      (asserts! (is-contract-owner) ERR_UNAUTHORIZED)
      (asserts! (> blocks u0) ERR_INVALID_DURATION)
      (asserts! (not (is-eq user tx-sender)) ERR_INVALID_PRICE)
      (map-set subscriptions user {expires-at: new-expiry})
      (ok {user: user, expires-at: new-expiry}))))

;; Public functions

;; Users pay to get access
(define-public (subscribe)
  (let (
    (price (var-get access-price))
    (duration (var-get access-duration))
    (current-sub (default-to {expires-at: u0} (map-get? subscriptions tx-sender)))
    (current-expiry (get expires-at current-sub))
    (base-time (if (> stacks-block-height current-expiry) stacks-block-height current-expiry))
    (new-expiry (+ base-time duration)))
    (begin
      ;; Transfer payment to contract
      (try! (stx-transfer? price tx-sender (as-contract tx-sender)))
      ;; Update revenue tracking
      (var-set total-revenue (+ (var-get total-revenue) price))
      ;; Set new subscription expiry
      (map-set subscriptions tx-sender {expires-at: new-expiry})
      (ok {
        subscriber: tx-sender, 
        expires-at: new-expiry,
        paid: price,
        duration: duration
      }))))

;; Extend existing subscription
(define-public (extend-subscription (additional-blocks uint))
  (let (
    (price (/ (* (var-get access-price) additional-blocks) (var-get access-duration)))
    (current-sub (default-to {expires-at: u0} (map-get? subscriptions tx-sender)))
    (current-expiry (get expires-at current-sub))
    (new-expiry (+ current-expiry additional-blocks)))
    (begin
      (asserts! (> additional-blocks u0) ERR_INVALID_DURATION)
      (asserts! (> current-expiry stacks-block-height) ERR_ACCESS_REVOKED)
      ;; Transfer proportional payment
      (try! (stx-transfer? price tx-sender (as-contract tx-sender)))
      ;; Update revenue tracking
      (var-set total-revenue (+ (var-get total-revenue) price))
      ;; Extend subscription
      (map-set subscriptions tx-sender {expires-at: new-expiry})
      (ok {
        subscriber: tx-sender,
        expires-at: new-expiry,
        paid: price,
        extended-by: additional-blocks
      }))))

;; Read-only functions

;; Check if user has access
(define-read-only (has-access (account principal))
  (let (
    (sub (default-to {expires-at: u0} (map-get? subscriptions account))))
    (ok (> (get expires-at sub) stacks-block-height))))

;; Get user subscription info
(define-read-only (get-subscription (account principal))
  (let (
    (sub (map-get? subscriptions account)))
    (match sub
      subscription (ok {
        expires-at: (get expires-at subscription),
        blocks-remaining: (if (> (get expires-at subscription) stacks-block-height)
                            (- (get expires-at subscription) stacks-block-height)
                            u0),
        is-active: (> (get expires-at subscription) stacks-block-height)
      })
      (ok {
        expires-at: u0,
        blocks-remaining: u0,
        is-active: false
      }))))

;; Get current contract settings
(define-read-only (get-settings)
  (ok {
    price: (var-get access-price),
    duration: (var-get access-duration),
    owner: (var-get contract-owner)
  }))

;; Get contract statistics
(define-read-only (get-stats)
  (ok {
    total-revenue: (var-get total-revenue),
    contract-balance: (stx-get-balance (as-contract tx-sender)),
    current-block: stacks-block-height
  }))

;; Calculate subscription cost for custom duration
(define-read-only (calculate-cost (blocks uint))
  (let (
    (base-price (var-get access-price))
    (base-duration (var-get access-duration)))
    (ok (/ (* base-price blocks) base-duration))))

;; Check if user's subscription is expiring soon
(define-read-only (is-expiring-soon (account principal) (warning-blocks uint))
  (let (
    (sub (default-to {expires-at: u0} (map-get? subscriptions account)))
    (expires-at (get expires-at sub))
    (warning-threshold (+ stacks-block-height warning-blocks)))
    (ok (and 
      (> expires-at stacks-block-height)
      (<= expires-at warning-threshold)))))

;; Get contract owner
(define-read-only (get-contract-owner)
  (ok (var-get contract-owner)))

;; Get time until subscription expires
(define-read-only (time-until-expiry (account principal))
  (let (
    (sub (default-to {expires-at: u0} (map-get? subscriptions account)))
    (expires-at (get expires-at sub)))
    (ok (if (> expires-at stacks-block-height)
          (- expires-at stacks-block-height)
          u0))))

;; Batch check access for multiple users
(define-read-only (batch-check-access (users (list 10 principal)))
  (ok (map has-access-helper users)))

;; Helper for batch access check
(define-private (has-access-helper (user principal))
  {
    user: user,
    has-access: (> (get expires-at (default-to {expires-at: u0} (map-get? subscriptions user))) stacks-block-height)
  })
