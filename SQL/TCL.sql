START TRANSACTION;

-- TABLE: demo_billing_ledger
CREATE TEMP TABLE demo_billing_ledger (
    entry_id INT PRIMARY KEY,
    charge_reference TEXT NOT NULL,
    entry_type TEXT NOT NULL CHECK (entry_type IN ('CHARGE', 'REFUND', 'REVERSAL')),
    amount_inr NUMERIC NOT NULL,
    CHECK (
        (entry_type = 'CHARGE' AND amount_inr > 0)
        OR (entry_type <> 'CHARGE' AND amount_inr < 0)
    )
) ON COMMIT DROP;

INSERT INTO demo_billing_ledger VALUES
    (1, 'DEMO-CHARGE', 'CHARGE', 1500),
    (2, 'DEMO-CHARGE', 'CHARGE', 1500);

INSERT INTO demo_billing_ledger VALUES (3, 'DEMO-CHARGE', 'REFUND', -1500);

SAVEPOINT before_duplicate_reversal;

-- Demonstrate rollback of an incorrect reversal before recording the correct amount.
INSERT INTO demo_billing_ledger VALUES (4, 'DEMO-CHARGE', 'REVERSAL', -150);

ROLLBACK TO SAVEPOINT before_duplicate_reversal;

INSERT INTO demo_billing_ledger VALUES (4, 'DEMO-CHARGE', 'REVERSAL', -1500);

SELECT SUM(amount_inr) AS expected_zero_balance FROM demo_billing_ledger;

DO $check$
DECLARE
    balance NUMERIC;
BEGIN
    SELECT SUM(amount_inr) INTO balance FROM demo_billing_ledger;

    IF balance IS DISTINCT FROM 0 THEN
        RAISE EXCEPTION 'TCL failed: balance=%', balance;
    END IF;

    RAISE NOTICE 'TCL check passed: balance = 0';
END $check$;

COMMIT;
