WITH Credit AS (
SELECT  
  * 
FROM(
SELECT 
  ROW_NUMBER() OVER (PARTITION BY lca.application_uuid_value ORDER BY application_start_date DESC) AS r,
  CAST(create_timestamp AS DATE) AS App_Start_Date,
  lca.application_uuid_value AS App_UUID,
  la.app_amount AS App_Amount,
  la.status AS App_Status,
  la.uw_decision_decision AS UW_Decision,
  la.adverse_action_declineReasons AS Decline_Reasons,
  CAST(la.credit_soft_fico AS FLOAT64) AS FICO,
  CAST(MTA2126 AS FLOAT64) AS MTA2126,
  CAST(COL3211 AS FLOAT64) AS COL3211,
  CAST(ALM6270 AS FLOAT64) AS ALM6270,
  CAST(IQT9425 AS FLOAT64) AS IQT9425,
  CAST(IQF9415 AS FLOAT64) AS IQF9415,
  CAST(ALL9220 AS FLOAT64) AS ALL9220,
  CAST(MTF8169 AS FLOAT64) AS MTF8169,
  CAST(subcode AS FLOAT64) AS FACTA_Subcode, 
  d.description AS Experian_Message,
  CASE 
  WHEN (((CAST(la.credit_soft_fico AS FLOAT64) < 620 AND CAST(create_timestamp AS DATE) <= '2020-03-20') OR (CAST(la.credit_soft_fico AS FLOAT64) < 640 AND CAST(create_timestamp AS DATE) > '2020-03-20')) AND CAST(la.credit_soft_fico AS FLOAT64) > 850) OR CAST(uw_packet_credit_score AS FLOAT64) IN (9000,9001,9002,9003) AND la.uw_decision_decision != 'DECLINE' AND la.status NOT IN ('DECLINED', 'CANCELLED') THEN 'FICO_Knockout_Failure'
  WHEN MTA2126 > 0 AND la.uw_decision_decision != 'DECLINE' AND la.status NOT IN ('DECLINED', 'CANCELLED') THEN 'Delinquent_30mdy_6mo_Knockout_Failure' 
  WHEN COL3211 > 0 AND la.uw_decision_decision != 'DECLINE' AND la.status NOT IN ('DECLINED', 'CANCELLED') THEN 'Non_Medical_Collections_Knockout_Failure'
  WHEN ALM6270 >= 60 AND la.uw_decision_decision != 'DECLINE' AND la.status NOT IN ('DECLINED', 'CANCELLED') THEN 'Worst_Trade_Status_12mo_non_medical_Knockout_Failure'
  WHEN IQT9425 - ( IQM9415 + IQA9415 ) >= 6 AND la.uw_decision_decision != 'DECLINE' AND la.status NOT IN ('DECLINED', 'CANCELLED') THEN 'Inquiries_Num_6mo_Knockout_Failure'
  WHEN IQF9415 > 2 AND la.uw_decision_decision != 'DECLINE' AND la.status NOT IN ('DECLINED', 'CANCELLED') THEN 'Finance_Inquiries_Num_No_Exceed_2_Knockout_Failure'
  WHEN ALL9220 <= 24 AND la.uw_decision_decision != 'DECLINE' AND la.status NOT IN ('DECLINED', 'CANCELLED') THEN 'No_Bankruptcy_24mo_Knockout_Failure'
  WHEN MTF8169 <= 60 AND la.uw_decision_decision != 'DECLINE' AND la.status NOT IN ('DECLINED', 'CANCELLED') THEN 'No_Foreclosure_60mo_Knockout_Failure'
  WHEN CAST(subcode AS FLOAT64) IN (16,23,26,28,31,33) AND la.uw_decision_decision != 'DECLINE' AND la.status NOT IN ('DECLINED', 'CANCELLED') THEN 'FACTA_Knockout_Failure' 
  WHEN (d.description LIKE '%subcode 5%' OR d.description LIKE '%subcode 25%' OR d.description LIKE '%subcode 13%' OR d.description LIKE '%subcode 14%' OR d.description LIKE '%subcode 27%') AND la.uw_decision_decision != 'DECLINE' AND la.status NOT IN ('DECLINED', 'CANCELLED') THEN 'Experian_Fraud_Shield_Knockouts_Failure'
  ELSE 'PASS'
  END AS Credit_Hard_Knockout_Failure
FROM  reporting.lkup_credit_attr lca 
JOIN rpt_staging.stg_uw_decision sud ON sud.application_uuid_value = lca.application_uuid_value
JOIN staging_evolved.fraud f ON f.application_uuid.value = lca.application_uuid_value
JOIN reporting.lkup_application la ON la.application_uuid_value = lca.application_uuid_value
LEFT JOIN UNNEST(decisions) AS d
LEFT JOIN ( SELECT * FROM rpt_staging.stg_credit_soft_elig_factors WHERE lower(type) LIKE '%facta%') s ON s.application_uuid_value = lca.application_uuid_value
WHERE product_type ='HELOC')
WHERE R = 1
ORDER BY App_Start_Date DESC),

F0 AS (
SELECT
  c.*,
  CAST(ad.avm_value_amount AS FLOAT64) AS AVM_Value_Amount,
  CAST(ad.prequal_avm_amount AS FLOAT64) AS Prequal_AVM_Amount,
  lp.land_use_code AS Land_Use_Case,
  lp.acres AS Acres,
  h.mortgage_status_indicator AS Mortgage_Status_Indicator,
  h.mortgage_payoff_date,
  h.mortgage_origination_date,
  h.mortgage_recording_date,
  lp.avm_last_sale_date,
  lp.current_transfer_sale_date,
  lp.last_market_sale_date,
  CASE WHEN CAST(ad.prequal_avm_amount AS FLOAT64) IS NULL AND CAST(ad.avm_value_amount AS FLOAT64) IS NULL THEN 'AVM_Knockout'
  WHEN (lp.land_use_code NOT IN(102,112,148,163) AND c.App_Start_Date <= '2020-03-20') OR (lp.land_use_code NOT IN(102,112,163) AND c.App_Start_Date >'2020-03-20') THEN 'Land_Use_Code_Knockout'
  WHEN lp.acres > 20 THEN 'Acres_Knockout'
  WHEN DATE_DIFF(CURRENT_DATE(), SAFE_CAST(COALESCE(lp.avm_last_sale_date, lp.current_transfer_sale_date, lp.last_market_sale_date) AS DATE), day) <= 90 THEN 'Last_Sale_Date_Knockout'
  WHEN h.mortgage_status_indicator IN ('F','U') AND h.mortgage_payoff_date IS NULL 
  AND (h.mortgage_recording_date IS NOT NULL OR h.mortgage_origination_date IS NOT NULL) 
  AND (h.mortgage_origination_date IS NOT NULL AND SAFE_CAST(h.mortgage_origination_date AS DATE) >= SAFE_CAST(COALESCE(lp.avm_last_sale_date, lp.current_transfer_sale_date, lp.last_market_sale_date) AS DATE))
  AND (h.mortgage_recording_date IS NOT NULL AND SAFE_CAST(h.mortgage_recording_date AS DATE) >= SAFE_CAST(COALESCE(lp.avm_last_sale_date, lp.current_transfer_sale_date, lp.last_market_sale_date) AS DATE)) 
  THEN 'Foreclosure_Knockout'
  ELSE 'PASS'
  END AS Property_Eligibility_Knockout,
  
  s.lien_summary.involuntary_lien.lien_on_property AS Involuntary_Lien_On_Property, 
  s.lien_summary.hoa_lien.lien_on_property AS HOA_Lien_On_Property,
  il.involuntary_lien_info.involuntary_lien_item.document_category AS Document_Category, 
  il.involuntary_lien_info.involuntary_lien_item.document_description AS Document_Description, 
  CAST(il.involuntary_lien_info.involuntary_lien_item.document_date.value AS DATE) AS Document_Date,

  il.involuntary_lien_info.state_code AS State_Code, 
  s.property_status_indicators.is_pace_lien AS Is_Pace_Lien,
  
  CASE WHEN s.lien_summary.involuntary_lien.lien_on_property IS TRUE OR s.lien_summary.hoa_lien.lien_on_property IS TRUE THEN 'YES' ELSE 'NO' END AS Involuntary_Lien_Exists,
  
  CASE WHEN (
  FICO >= 680 AND 
 (il.involuntary_lien_info.involuntary_lien_item.document_category = 'NOTICE' AND il.involuntary_lien_info.involuntary_lien_item.document_description = 'NOTICE') 
  AND s.property_status_indicators.is_pace_lien IS FALSE) IS TRUE THEN 'YES' ELSE 'NO' END AS Exception1_Exists,
  
  CASE WHEN (il.involuntary_lien_info.involuntary_lien_item.document_category = 'FEDERAL TAX LIEN' AND DATE_DIFF( Current_Date, CAST(il.involuntary_lien_info.involuntary_lien_item.document_date.value AS DATE), MONTH) > 120) IS TRUE
  OR
  (il.involuntary_lien_info.involuntary_lien_item.document_category = 'MECHANICS LIEN' AND DATE_DIFF( Current_Date, CAST(il.involuntary_lien_info.involuntary_lien_item.document_date.value AS DATE), MONTH) > 24) IS TRUE
  OR
  (il.involuntary_lien_info.involuntary_lien_item.document_category = 'STATE TAX LIEN' AND il.involuntary_lien_info.state_code IN('NH', 'IL', 'CA', 'NJ', 'VA', 'WI', 'FL', 'HI', 'CT', 'OH', 'VT', 'IA', 'KY', 'LA', 'MD') AND DATE_DIFF( Current_Date, CAST(il.involuntary_lien_info.involuntary_lien_item.document_date.value AS DATE), MONTH) > 240) IS TRUE
  OR 
  (il.involuntary_lien_info.involuntary_lien_item.document_category = 'STATE TAX LIEN' AND il.involuntary_lien_info.state_code IN('AL', 'AZ', 'AR', 'DE', 'IN', 'ME', 'MA', 'MN', 'NM', 'TN', 'WA', 'WY', 'WV', 'KS', 'SC', 'GA', 'OK', 'NE') AND DATE_DIFF( Current_Date, CAST(il.involuntary_lien_info.involuntary_lien_item.document_date.value AS DATE), MONTH) > 120) IS TRUE
  OR  
  (il.involuntary_lien_info.involuntary_lien_item.document_category = 'STATE TAX LIEN' AND il.involuntary_lien_info.state_code IN('SD', 'UT', 'ID', 'CO', 'MI', 'MS') AND DATE_DIFF( Current_Date, CAST(il.involuntary_lien_info.involuntary_lien_item.document_date.value AS DATE), MONTH) > 84) IS TRUE
  OR  
  (il.involuntary_lien_info.involuntary_lien_item.document_category IN ('JUDGMENT', 'LIEN') AND il.involuntary_lien_info.state_code IN('MD', 'DC', 'NM', 'KY', 'ME', 'MA', 'CT', 'NJ', 'RI') AND DATE_DIFF( Current_Date, CAST(il.involuntary_lien_info.involuntary_lien_item.document_date.value AS DATE), MONTH) > 240) IS TRUE
  OR
  (il.involuntary_lien_info.involuntary_lien_item.document_category IN ('JUDGMENT', 'LIEN') AND il.involuntary_lien_info.state_code IN('AR', 'AL', 'IA','DE', 'IN', 'MN', 'TN', 'WA', 'WV', 'SC', 'CA', 'FL', 'VA', 'WI', 'SD', 'LA', 'TX', 'MT', 'NC', 'OR', 'MO', 'AZ', 'UT', 'VT', 'AK') AND 
  DATE_DIFF( Current_Date, CAST(il.involuntary_lien_info.involuntary_lien_item.document_date.value AS DATE), MONTH) > 120) IS TRUE
  OR 
  (il.involuntary_lien_info.involuntary_lien_item.document_category IN ('JUDGMENT', 'LIEN') AND il.involuntary_lien_info.state_code IN('WY', 'KS', 'OK', 'OH', 'ID', 'MI', 'PA', 'NE', 'NH', 'CO', 'NV', 'GA', 'IL', 'MI') AND DATE_DIFF( Current_Date, CAST(il.involuntary_lien_info.involuntary_lien_item.document_date.value AS DATE), MONTH) > 84) IS TRUE THEN 'YES' ELSE 'NO' END AS Exception2_Exists,
  
  CASE WHEN (il.involuntary_lien_info.involuntary_lien_item.document_category IN ('FEDERAL TAX LIEN', 'MECHANICS LIEN', 'STATE TAX LIEN','JUDGMENT', 'LIEN') AND  CAST(il.involuntary_lien_info.involuntary_lien_item.document_date.value AS DATE) IS NULL) THEN 'YES' ELSE 'NO' END AS Exception3_Exists,
  
  DATE_DIFF( Current_Date, CAST(il.involuntary_lien_info.involuntary_lien_item.document_date.value AS DATE), MONTH) AS Date_Difference_By_Month
FROM reporting.application_details ad
JOIN reporting.lkup_datatree_summary s ON s.application_uuid.value = ad.application_uuid_value
JOIN reporting.lkup_datatree_involuntary_liens il ON il.application_uuid.value = ad.application_uuid_value
JOIN reporting.lkup_application la ON la.application_uuid_value = ad.application_uuid_value
JOIN reporting.lkup_property lp ON lp.property_uuid_value = ad.property_uuid_value
JOIN reporting.f_heloc_property_financial_history h ON h.application_uuid = ad.application_uuid_value
JOIN Credit c ON c.App_UUID = s.application_uuid.value
),

Property AS (
SELECT 
  *,
  CASE  
  WHEN (App_Status NOT IN('CANCELLED','DECLINED') AND UW_Decision != 'DECLINE') AND (Involuntary_Lien_Decline like '%Involuntary_Lien_Knockout%' OR Property_Eligibility_Knockout != 'PASS' OR Credit_Hard_Knockout_Failure != 'PASS') THEN 'Apps should have been declined, but were not declined'
  WHEN App_Status = 'DECLINED' AND Decline_Reasons IN ('Other: Involuntary lien', 'Property value or type of collateral not sufficient', 'Credit application incomplete','Delinquent past or present credit obligations with others', 'Number of recent inquiries on credit bureau report',
  'Number of recent inquiries on credit bureau report', 'No credit file','We were unable to verify your identity', 'Credit score unavailable', 'Limited credit experience','Your credit score is below our minimum requirement', 'Other: OFAC check failure - contact OFAC') 
  AND Involuntary_Lien_Decline = 'PASS' AND Property_Eligibility_Knockout = 'PASS' AND Credit_Hard_Knockout_Failure = 'PASS'
  AND App_UUID NOT IN (SELECT App_UUID FROM F0 WHERE Involuntary_Lien_Exists = 'YES' AND Exception1_Exists = 'NO'  AND Exception2_Exists = 'NO' AND Exception3_Exists = 'NO' )
  THEN 'Apps should have not been declined, but were declined'
  ELSE 'Apps were declined correctly'
  END AS  Credit_Property_invol_Decline_Failure
FROM (
SELECT 
   *,
   CASE 
   WHEN Involuntary_Lien_Exists = 'YES' AND Exception1_Exists = 'NO'  AND Exception2_Exists = 'NO' AND Exception3_Exists = 'NO' AND Document_Category IS NOT NULL AND Document_Description IS NOT NULL AND Document_Date IS NOT NULL THEN 'Involuntary_Lien_Knockout(DT returns)'
   WHEN Involuntary_Lien_Exists = 'YES' AND Exception1_Exists = 'NO'  AND Exception2_Exists = 'NO' AND Exception3_Exists = 'NO' AND Document_Category IS NULL AND Document_Description IS  NULL AND Document_Date IS  NULL THEN 'Involuntary_Lien_Knockout(DT no returns)'
   ELSE 'PASS'
   END AS Involuntary_Lien_Decline,
   ROW_NUMBER() OVER(PARTITION BY App_UUID ORDER BY App_Start_Date DESC) AS rank
FROM F0
WHERE UW_Decision IS NOT NULL 
ORDER BY App_Start_Date DESC))

SELECT * FROM Property
WHERE rank = 1 
 AND Credit_Property_invol_Decline_Failure != 'Apps were declined correctly' 

ORDER BY App_Start_Date DESC, App_UUID
