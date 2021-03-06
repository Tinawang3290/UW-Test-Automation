--Corelogic
SELECT 
  f.application_uuid, f.mortgage_amount, f.mortgage_status_indicator, h.original_document_number, f.mortgage_recording_date, f.mortgage_origination_date, f.mortgage_payoff_date, f.mortgage_release_date,
  SAFE_CAST(COALESCE(lp.avm_last_sale_date, lp.current_transfer_sale_date, lp.last_market_sale_date) AS DATE) AS Last_Sale_Date,
--   CAST(recording_information.first_mortgage_date.value AS DATE) AS First_Mortgage_Date,
  First_Mortgage_Date,
  CAST(MTA5020 AS FLOAT64) AS MTA5020,
--   CASE 
--   WHEN (recording_information.first_mortgage_date.value IS NOT NULL AND mortgage_status_indicator != 'O' AND DATE_DIFF(SAFE_CAST(COALESCE(lp.avm_last_sale_date, lp.current_transfer_sale_date, lp.last_market_sale_date) AS DATE), CAST(recording_information.first_mortgage_date.value AS DATE), DAY) <= 10) 
--   OR
--   (recording_information.first_mortgage_date.value IS NOT NULL AND mortgage_status_indicator != 'O' AND DATE_DIFF(SAFE_CAST(COALESCE(lp.avm_last_sale_date, lp.current_transfer_sale_date, lp.last_market_sale_date) AS DATE), CAST(recording_information.first_mortgage_date.value AS DATE), DAY) > 10 AND CAST(MTA5020 AS FLOAT64) > 0)
--   OR 
--   (recording_information.first_mortgage_date.value IS NULL AND mortgage_status_indicator != 'O' AND CAST(MTA5020 AS FLOAT64) > 0)
--   OR
--   (recording_information.first_mortgage_date.value IS NOT NULL AND mortgage_status_indicator IS NULL  )
--   THEN CAST(MTA5020 AS FLOAT64)

-- Identify Open Lien Data
  CASE WHEN 
  DATE_DIFF(SAFE_CAST(COALESCE(lp.avm_last_sale_date, lp.current_transfer_sale_date, lp.last_market_sale_date) AS DATE) , CAST(f.mortgage_origination_date AS DATE), DAY) > 7 
  OR 
  DATE_DIFF(SAFE_CAST(COALESCE(lp.avm_last_sale_date, lp.current_transfer_sale_date, lp.last_market_sale_date) AS DATE), CAST(f.mortgage_recording_date AS DATE), DAY) > 7
  OR 
  SAFE_CAST(COALESCE(lp.avm_last_sale_date, lp.current_transfer_sale_date, lp.last_market_sale_date) AS DATE) IS NULL
  OR
  f.mortgage_origination_date IS NULL
  OR 
  f.mortgage_recording_date IS NULL
  OR
  f.mortgage_amount IS NULL
  THEN 'Ignore' ELSE 'Show' END AS CoreLogic_Display
FROM reporting.f_heloc_property_financial_history f
LEFT JOIN (
SELECT 
  p.application_uuid.value AS Application_UUID_Value,
  fa.original_document_number, 
  CAST(recording_information.first_mortgage_date.value AS DATE) AS First_Mortgage_Date 
FROM staging_evolved.property_financial_history p 
LEFT JOIN UNNEST(finance_history_attributes) AS fa) h ON h.application_uuid_value = f.application_uuid
LEFT JOIN reporting.lkup_credit_attr lca ON lca.application_uuid_value = f.application_uuid
LEFT JOIN reporting.lkup_property lp ON lp.property_uuid_value = f.property_uuid
WHERE f.mortgage_status_indicator = 'O' AND  LENGTH(f.mortgage_payoff_date) < 1 AND f.application_uuid = '6cd86dac-21ac-4eea-91ca-283283977e01'

-- SELECT di FROM staging_evolved.property_financial_history
-- WHERE application_uuid.value IN('6cd86dac-21ac-4eea-91ca-283283977e01', '17023b2d-cf29-446f-ac3c-f74deecbb5f5')




 SELECT * FROM(
 SELECT 
  application_uuid_value,
  mortgage_payoff_date.value AS Mortgage_Payoff_Date,
  mortgage_status_indicator AS Mortgage_Status_Indicator,
  mortgage_origination_date.value AS Mortgage_Origination_Date,
  mortgage_recording_date.value AS Mortgage_Recording_Date,
  mortgage_amount.amount AS Mortgage_Amount,
  original_document_number AS Original_Document_Number, 
  SAFE_CAST(COALESCE(lp.avm_last_sale_date, lp.current_transfer_sale_date, lp.last_market_sale_date) AS DATE) AS Last_Sale_Date,
  CASE WHEN 
  DATE_DIFF(SAFE_CAST(COALESCE(lp.avm_last_sale_date, lp.current_transfer_sale_date, lp.last_market_sale_date) AS DATE) , SAFE_CAST(mortgage_origination_date.value AS DATE), DAY) > 7 
  OR 
  DATE_DIFF(SAFE_CAST(COALESCE(lp.avm_last_sale_date, lp.current_transfer_sale_date, lp.last_market_sale_date) AS DATE), SAFE_CAST(mortgage_recording_date.value AS DATE), DAY) > 7
  OR 
  (SAFE_CAST(COALESCE(lp.avm_last_sale_date, lp.current_transfer_sale_date, lp.last_market_sale_date) AS DATE) IS NULL AND mortgage_payoff_date.value IS NOT NULL AND mortgage_status_indicator != 'O')
  OR
  mortgage_origination_date.value IS NULL
  OR 
  mortgage_recording_date.value IS NULL
  OR
  mortgage_amount.amount IS NULL
  THEN 'Ignore' ELSE 'Show' END AS CoreLogic_Display,
  row_number() OVER (PARTITION BY property_uuid,
                                  application_uuid_value,
                                  mortgage_document_number,
                                  mortgage_recording_date.value
                     ORDER BY (updated_seconds+updated_nanos)desc,
                              (created_seconds + created_nanos) desc,
                              length(lender) desc) rnum
 FROM rpt_staging.stg_property_financial_history s
 LEFT JOIN reporting.lkup_property lp ON lp.property_uuid_value = s.property_uuid
 -- WHERE application_uuid_value IN ( '6cd86dac-21ac-4eea-91ca-283283977e01', '17023b2d-cf29-446f-ac3c-f74deecbb5f5')
 )
 WHERE rnum = 1 AND CoreLogic_Display = 'Show'
 ORDER BY application_uuid_value
 
 SELECT 
  s.application_uuid_value,
  app_start_date,
  mortgage_payoff_date.value AS Mortgage_Payoff_Date,
  mortgage_status_indicator AS Mortgage_Status_Indicator,
  mortgage_origination_date.value AS Mortgage_Origination_Date,
  mortgage_recording_date.value AS Mortgage_Recording_Date,
  mortgage_amount.amount AS Mortgage_Amount,
  original_document_number AS Original_Document_Number, 
  SAFE_CAST(COALESCE(lp.avm_last_sale_date, lp.current_transfer_sale_date, lp.last_market_sale_date) AS DATE) AS Last_Sale_Date,
 FROM rpt_staging.stg_property_financial_history s
 LEFT JOIN reporting.lkup_property lp ON lp.property_uuid_value = s.property_uuid 
 JOIN reporting.application_details ad ON ad.application_uuid_value = s.application_uuid_value
 WHERE LENGTH(mortgage_payoff_date.value) < 1 AND mortgage_status_indicator = 'O' 
 AND (DATE_DIFF(SAFE_CAST(COALESCE(lp.avm_last_sale_date, lp.current_transfer_sale_date, lp.last_market_sale_date) AS DATE) , SAFE_CAST(mortgage_origination_date.value AS DATE), DAY) > 7 
  OR 
  DATE_DIFF(SAFE_CAST(COALESCE(lp.avm_last_sale_date, lp.current_transfer_sale_date, lp.last_market_sale_date) AS DATE), SAFE_CAST(mortgage_recording_date.value AS DATE), DAY) > 7)
 ORDER BY app_start_date desc, application_uuid_value
 
 
-- DataTree
SELECT 
  application_uuid.value AS Application_UUID_Value,
  t.type_description AS Type_Description, 
  t.tx_date.value AS Tx_Date,
  t.sale_date.value AS Sale_Date,
  t.lien_position AS Lien_Postion,
  t.original_recording_date.value AS Original_Recording_Date, 
  t.loan_amount.amount AS Loan_Amount,
  t.doc_id AS Doc_ID,
  DATE_DIFF(CAST(t.sale_date.value AS DATE), CAST(t.tx_date.value AS DATE), DAY),
  CASE WHEN 
--   t.type_description = 'FINANCE' AND
  DATE_DIFF(CAST(t.sale_date.value AS DATE), CAST(t.tx_date.value AS DATE), DAY) > 7
  OR 
  t.lien_position IS NULL
  OR
  (t.tx_date.value IS NULL
  AND  
  t.original_recording_date.value IS NULL)
  OR
  t.loan_amount.amount IS NULL
  THEN 'Ignore' ELSE 'Show' END AS Datatree_Display
 
FROM staging_evolved.property_data_proto_external_property_datatree_total_view_report_r1
LEFT JOIN UNNEST(transaction) AS t
WHERE application_uuid.value = '6cd86dac-21ac-4eea-91ca-283283977e01'
AND t.type_description = 'FINANCE'


-- -- Experian
-- SELECT 
--   cs.application_uuid_value,
--  --  ad.app_start_date,
--   cs.open_date, 
--   cs.status_date,
--   cs.account_type, 
--   cs.balance_date,
--   cs.amounts_amounts AS Amount
  
-- FROM rpt_staging.stg_credit_tradelines cs
-- JOIN reporting.application_details ad ON ad.application_uuid_value = cs.application_uuid_value
-- WHERE cs.application_uuid_value = '6cd86dac-21ac-4eea-91ca-283283977e01' AND cs.account_type IN ('19', '26')
-- ORDER BY open_date DESC


-- Experian
SELECT 
  ct.application_uuid_value, 
  DATE(ad.app_start_date) AS App_Start_Date, 
  open_date, 
  status_date, 
  account_type, 
  balance_amount AS Balance_Amount, 
  amounts_amounts AS Amount, 
  amounts_types , 
  status, 
  open,
  CASE 
  WHEN account_type IN ('89','47', '6D') THEN 'Exception1'
  WHEN status IN ('05','10','67','69') THEN 'Exception2'
  WHEN ((account_type IN ('26','19') AND DATE_DIFF(CAST(app_start_date AS DATE), CAST(t.open_date AS DATE), DAY) <= 30 AND open = false) OR (account_type IN ('26','19') AND ABS(DATE_DIFF(CAST(app_start_date AS DATE),CAST(c.status_date AS DATE), DAY)) <= 30 AND open = false)) THEN 'Exception3'
  END AS Experian_Display
FROM rpt_staging.stg_credit_tradelines ct
JOIN reporting.application_details ad ON ad.application_uuid_value = ct.application_uuid_value
LEFT JOIN (SELECT application_uuid_value, CAST(open_date AS DATE) AS Open_Date FROM rpt_staging.stg_credit_tradelines WHERE OPEN is true AND account_type IN ('19', '26') ) t ON t.application_uuid_value =  ct.application_uuid_value
LEFT JOIN (SELECT application_uuid_value, CAST(status_date AS DATE) AS Status_Date FROM rpt_staging.stg_credit_tradelines WHERE OPEN is false AND account_type IN ('19', '26')) c ON c.application_uuid_value =  ct.application_uuid_value
WHERE ct.application_uuid_value = '6cd86dac-21ac-4eea-91ca-283283977e01' AND ct.account_type IN ('19', '26')
-- ORDER BY open_date DESC 
