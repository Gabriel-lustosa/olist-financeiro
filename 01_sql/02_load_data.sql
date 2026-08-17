

SELECT TOP 10
      o.order_id,
      o.order_status, 
      o.order_purchase_timestamp,
      p.payment_type,
      p.payment_value
FROM orders  [o]
INNER JOIN  order_payments [p]
ON o.order_id = p.order_id;


