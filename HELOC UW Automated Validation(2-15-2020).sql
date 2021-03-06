
--Credit Hard Knockout
WITH Credit AS (
SELECT 
  CASE 
  WHEN (CAST(uw_packet_credit_score AS FLOAT64) <= 620 AND CAST(uw_packet_credit_score AS FLOAT64) > 850) OR CAST(uw_packet_credit_score AS FLOAT6) IN (9000,9001,9002,9003) THEN 'YES'
  ELSE 'NO'
  END AS FICO_Knockout,
  CASE 
  WHEN MTA2126 > 0 THEN 'YES' ELSE 'NO' END AS Delinquent_30mdy_6mo_Knockout,
  CASE 
  WHEN COL3211 > 0 THEN 'YES' ELSE 'NO' END AS Non_Medical_Collections_Knockout,
  CASE 
  WHEN ALM6270 >= 60 THEN 'YES' ELSE 'NO' END AS Worst_Trade_Status_12mo_non_medical_Knockout,
  CASE 
  WHEN IQT9425 - ( IQM9415 + IQA9415 ) >= 6 THEN 'YES' ELSE 'NO' END AS Inquiries_Num_Knockout,
  CASE 
  WHEN IQF9415 > 2 THEN 'YES' ELSE 'NO' END AS Finance_Inquiries_Num_No_Exceed_2_Knockout,
  CASE 
  WHEN ALL9220 <= 24 THEN  'YES' ELSE 'NO' END AS No_Bankruptcy_24mo_Knockout,
  CASE 
  WHEN MTF8169 <= 60 THEN 'YES' ELSE 'NO' END AS No_Foreclosure_60mo_Knockout,
  
-- Find the message that FACTA resides.
  
  CASE 
  WHEN d.description LIKE '%subcode 5%' OR d.description LIKE '%subcode 25%' OR d.description LIKE '%subcode 13%' OR d.description LIKE '%subcode 14%' OR d.description LIKE '%subcode 27%' THEN 'YES' ELSE 'NO' END AS Experian_Fraud_Shield_Knockouts

FROM `figure-production.reporting.lkup_credit_attr` lca 
JOIN `figure-production.rpt_staging.stg_uw_decision` sud ON sud.application_uuid_value = lca.application_uuid_value
JOIN `figure-production.staging_evolved.fraud` f ON f.application_uuid.value = lca.application_uuid_value
LEFT JOIN UNNEST(decisions) AS d
WHERE product_type ='HELOC'),

-- Property Criteria 
  
F0 AS (
SELECT
  la.create_timestamp AS App_Created_Dt,
  s.application_uuid.value AS App_UUID,
  CASE 
  WHEN property_status = 'NoneFound' THEN 'YES' ELSE 'NO' END AS AVM_Knockout,
  CASE 
  WHEN land_use_code NOT IN(102,112,148,163) THEN 'YES' ELSE 'NO' END AS Land_Use_Code_Knockout,
  CASE 
  WHEN acres > 20 THEN 'YES' ELSE 'NO' END AS Acres_Knockout,
  last_market_sale_date,
  CASE
  WHEN DATE_DIFF(CURRENT_DATE(), CAST(last_market_sale_date AS DATE), day) <= 90 THEN 'YES' ELSE 'NO' END AS Last_Sale_Date_Knockout, 
  la.credit_soft_fico AS FICO,
  la.status  AS App_Status,
  la.uw_decision_decision AS UW_Decision,
  la.adverse_action_declineReasons AS Decline_Reasons,
  S.lien_summary.involuntary_lien.lien_on_property AS Involuntary_Lien_On_Property, 
  S.lien_summary.hoa_lien.lien_on_property AS HOA_Lien_On_Property,
  il.involuntary_lien_info.involuntary_lien_item.document_category AS Document_Category, 
  il.involuntary_lien_info.involuntary_lien_item.document_description AS Document_Description, 
  CAST(il.involuntary_lien_info.involuntary_lien_item.document_date.value AS DATE) AS Document_Date,
  CURRENT_DATE() AS Current_Date,
  il.involuntary_lien_info.state_code AS State_Code, 
  S.property_status_indicators.is_pace_lien AS Is_Pace_Lien
FROM `figure-production.reporting.lkup_datatree_summary` s
JOIN `figure-production.reporting.lkup_datatree_involuntary_liens` il ON il.application_uuid.value = s.application_uuid.value
JOIN `figure-production.reporting.lkup_application` la ON la.application_uuid_value = s.application_uuid.value
JOIN `figure-production.reporting.lkup_property` lp ON lp.identity_uuid_value = s. identity_uuid.value
),

F1 AS (
SELECT 
  *
FROM( SELECT 
  *,
   
   CASE 
   WHEN Involuntary_Lien_On_Property IS TRUE OR HOA_Lien_On_Property IS TRUE THEN 'YES'
   ELSE 'NO'
   END AS Involuntary_Lien_Exists,
    CASE WHEN (FICO >= 680 AND (Document_Category = 'NOTICE' AND Document_Description = 'NOTICE') AND Is_Pace_Lien IS FALSE) IS TRUE THEN 'YES'
    ELSE 'NO'
    END AS Exception1_Exists,
    
    CASE WHEN (Document_Category = 'FEDERAL TAX LIEN' AND DATE_DIFF( Current_Date, Document_Date, YEAR) > 10) IS TRUE
    OR
    (Document_Category = 'MECHANICS LIEN' AND DATE_DIFF( Current_Date, Document_Date, YEAR) > 2) IS TRUE
    OR
    (Document_Category = 'STATE TAX LIEN' AND State_Code IN('NH', 'IL', 'CA', 'NJ', 'VA', 'WI', 'FL', 'HI', 'CT', 'OH', 'VT', 'IA', 'KY', 'LA', 'MD') AND DATE_DIFF( Current_Date, Document_Date, YEAR) > 20) IS TRUE
    OR 
    (Document_Category = 'STATE TAX LIEN' AND State_Code IN( 'AL', 'AZ', 'AR', 'DE', 'IN', 'ME', 'MA', 'MN', 'NM', 'TN', 'WA', 'WY', 'WV', 'KS', 'SC', 'GA', 'OK', 'NE') AND DATE_DIFF( Current_Date, Document_Date, YEAR) > 10) IS TRUE
    OR  
    (Document_Category = 'STATE TAX LIEN' AND State_Code IN( 'SD', 'UT', 'ID', 'CO', 'MI', 'MS') AND DATE_DIFF( Current_Date, Document_Date, YEAR) > 7) IS TRUE
    OR  
    (Document_Category IN ('JUDGMENT', 'LIEN') AND State_Code IN( 'MD', 'DC', 'NM', 'KY', 'ME', 'MA', 'CT', 'NJ', 'RI') AND DATE_DIFF( Current_Date, Document_Date, YEAR) > 20) IS TRUE
    OR
    (Document_Category IN ('JUDGMENT', 'LIEN') AND State_Code IN( 'AR', 'AL', 'IA','DE', 'IN', 'MN', 'TN', 'WA', 'WV', 'SC', 'CA', 'FL', 'VA', 'WI', 'SD', 'LA', 'TX', 'MT', 'NC', 'OR', 'MO', 'AZ', 'UT', 'VT', 'AK') AND DATE_DIFF( Current_Date, Document_Date, YEAR) > 10) IS TRUE
    OR 
    (Document_Category IN ('JUDGMENT', 'LIEN') AND State_Code IN( 'WY', 'KS', 'OK', 'OH', 'ID', 'MI', 'PA', 'NE', 'NH', 'CO', 'NV', 'GA', 'IL', 'MI') AND DATE_DIFF( Current_Date, Document_Date, YEAR) > 7) IS TRUE THEN 'YES'
    ELSE 'NO'
    END AS Exception2_Exists,
    
    CASE 
    WHEN (Document_Category IN ('FEDERAL TAX LIEN', 'MECHANICS LIEN', 'STATE TAX LIEN','JUDGMENT', 'LIEN') AND  Document_Date IS NULL) THEN 'YES'
    ELSE 'NO'
    END AS Exception3_Exists,
    
  DATE_DIFF( Current_Date, Document_Date, YEAR) AS Date_Difference_By_Year
FROM F0)),

Property AS (
SELECT 
  *,
  CASE  
  WHEN (App_Status != 'DECLINED' AND UW_Decision != 'DECLINE') AND Involuntary_Lien_Decline_Recommendation = 'DECLINE' THEN 'Apps should have been declined, but were not declined'
  WHEN App_Status = 'DECLINED' AND Decline_Reasons = 'Other: Involuntary lien' AND Involuntary_Lien_Decline_Recommendation = 'DO NOT DECLINE' 
  AND App_UUID NOT IN (SELECT App_UUID FROM F1 WHERE Involuntary_Lien_Exists = 'YES' AND Exception1_Exists = 'NO'  AND Exception2_Exists = 'NO' AND Exception3_Exists = 'NO' )
  THEN 'Apps should have not been declined, but were declined'
  ELSE 'Apps were declined correctly'
  END AS  Involuntary_Lien_Decline_Failure
FROM (
SELECT 
   *,
   CASE 
   WHEN Involuntary_Lien_Exists = 'YES' AND Exception1_Exists = 'NO'  AND Exception2_Exists = 'NO' AND Exception3_Exists = 'NO' THEN 'DECLINE'
   ELSE 'DO NOT DECLINE'
   END AS Involuntary_Lien_Decline_Recommendation,
FROM F1
WHERE UW_Decision IS NOT NULL
ORDER BY App_Created_Dt DESC))











 



-- F0 AS (
-- SELECT 
--   la. application_uuid_value,
--   CASE 
--   WHEN property_status = 'NoneFound' THEN 'YES' ELSE 'NO' END AS AVM_Knockout,
--   CASE 
--   WHEN land_use_code NOT IN(102,112,148.,163) THEN 'YES' ELSE 'NO' END AS Land_Use_Code_Knockout,
--   CASE 
--   WHEN acres > 20 THEN 'YES' ELSE 'NO' END AS Acres_Knockout,
--   CASE
--   WHEN last_market_sale_date <= 90 THEN 'YES' ELSE 'NO' END AS Last_Sale_Date_Knockout
-- FROM `figure-production.reporting.lkup_property` lp
-- JOIN `figure-production.reporting.lkup_application` la ON lp.identity_uuid_value = la.identity_uuid_value),


-- SELECT * FROM `figure-production.staging_evolved.fraud`
-- LEFT JOIN UNNEST(decisions) AS d
-- WHERE lower(d.description) like '% inquiry_data.person_name.audit_fields.message %' 
-- -- WHERE d.description LIKE '%subcode 5%' OR d.description LIKE '%subcode 25%' OR d.description LIKE '%subcode 13%' OR d.description LIKE '%subcode 14%' OR d.description LIKE '%subcode 27%' 
-- ORDER BY application_uuid.value



-- CLTV TEST 
WITH F AS (
SELECT *, 
  CASE
  WHEN T_AVM_Value < 100000 THEN  T_AVM_Value *0.5
  WHEN T_AVM_Value >= 100000 AND  IFNULL(avm_fsd, prequal_avm_fsd) <= 13 THEN  T_AVM_Value
  WHEN T_AVM_Value >= 100000 AND  IFNULL(avm_fsd, prequal_avm_fsd) >13  THEN T_AVM_Value *(1-  IFNULL(avm_fsd, prequal_avm_fsd)/200)
  END AS T_Adjusted_Collateral_Value,
FROM (
SELECT
  la.create_timestamp AS App_Created_Dt,
  s.application_uuid.value AS App_UUID,
  
--   CASE 
--   WHEN lp.property_status = 'NoneFound' THEN 'YES' ELSE 'NO' END AS AVM_Knockout,
--   CASE 
--   WHEN lp.land_use_code NOT IN(102,112,148,163) THEN 'YES' ELSE 'NO' END AS Land_Use_Code_Knockout,
--   CASE 
--   WHEN lp.acres > 20 THEN 'YES' ELSE 'NO' END AS Acres_Knockout,
--   lp.last_market_sale_date,
--   CASE
--   WHEN DATE_DIFF(CURRENT_DATE(), CAST(lp.last_market_sale_date AS DATE), day) <= 90 THEN 'YES' ELSE 'NO' END AS Last_Sale_Date_Knockout, 
--   la.credit_soft_fico AS FICO,
--   la.status  AS App_Status,
--   la.uw_decision_decision AS UW_Decision,
--   la.adverse_action_declineReasons AS Decline_Reasons,
--   s.lien_summary.involuntary_lien.lien_on_property AS Involuntary_Lien_On_Property, 
--   s.lien_summary.hoa_lien.lien_on_property AS HOA_Lien_On_Property,
--   il.involuntary_lien_info.involuntary_lien_item.document_category AS Document_Category, 
--   il.involuntary_lien_info.involuntary_lien_item.document_description AS Document_Description, 
--   CAST(il.involuntary_lien_info.involuntary_lien_item.document_date.value AS DATE) AS Document_Date,
--   CURRENT_DATE() AS Current_Date,
--   il.involuntary_lien_info.state_code AS State_Code, 
--   s.property_status_indicators.is_pace_lien AS Is_Pace_Lien,
  lp.avm_value_amount ,
  sud.uw_packet_home_amount,
  CASE 
  WHEN lp.avm_value_amount IS NULL OR (lp.avm_value_amount >= sud.uw_packet_home_amount) THEN  sud.uw_packet_home_amount ELSE lp.avm_value_amount END AS T_AVM_Value,
  lp.avm_fsd, 
  lp.prequal_avm_fsd,
  la.uw_packet_amt_owed,
  la.adjusted_home_amount, 
FROM `figure-production.reporting.lkup_datatree_summary` s
JOIN `figure-production.reporting.lkup_datatree_involuntary_liens` il ON il.application_uuid.value = s.application_uuid.value
JOIN `figure-production.reporting.lkup_application` la ON la.application_uuid_value = s.application_uuid.value
JOIN `figure-production.reporting.lkup_property` lp ON lp.identity_uuid_value = s.identity_uuid.value
JOIN `figure-production.rpt_staging.stg_uw_decision` sud ON sud.identity_uuid_value = s. identity_uuid.value
))
SELECT * FROM F
WHERE  ROUND(adjusted_home_amount,0) !=  ROUND(T_Adjusted_Collateral_Value,0)

SELECT avm_value_amount  FROM  `figure-production.reporting.lkup_property`
where identity_uuid_value = 'b0d84349-b623-4b61-8476-ca09c5fb4a60'
