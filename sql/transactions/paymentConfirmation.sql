START TRANSACTION;

UPDATE client_payments
SET visit_paid = 1,
    payment_status = 'completed',
    payment_date = NOW(),
    payment_method = 'card'
WHERE payment_intent_id = :stripe_payment_intent_id;

UPDATE visits v
JOIN client_payments p ON p.visit_id = v.visit_id
SET v.visit_is_locked = 1
WHERE p.payment_intent_id = :stripe_payment_intent_id
  AND p.visit_type = '1';

SELECT p.payment_id, p.amount, p.payment_status, u.name, u.surname, u.email
FROM client_payments p
JOIN users u ON u.id = p.user_id
WHERE p.payment_intent_id = :stripe_payment_intent_id;

COMMIT;
-- On any failure between START TRANSACTION and COMMIT: ROLLBACK;
