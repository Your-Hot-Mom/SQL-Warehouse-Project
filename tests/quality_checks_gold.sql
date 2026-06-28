SELECT cst_id, COUNT(*)
FROM
(
SELECT 
ci.cst_id,
ci.cst_key,
ci.cst_firstname,
ci.cst_lastname,
ci.cst_marital_status,
ci.cst_gndr,
ci.cst_create_date,
ca.bdate,
ca.gen,
la.cntry
FROM [silver].[crm_cust_info] AS ci
LEFT JOIN [silver].[erp_cust_az12] AS ca
ON ci.cst_key = ca.cid
LEFT JOIN [silver].[erp_loc_a101] AS la
ON ci.cst_key = la.cid
)t
GROUP BY cst_id
HAVING COUNT(*) > 1

SELECT DISTINCT
ci.cst_gndr,
ca.gen,
CASE WHEN UPPER(TRIM(ci.cst_gndr)) != 'N/A' THEN ci.cst_gndr -- CRM is the Master for gender
	ELSE COALESCE(ca.gen, 'N/A')
	END as new_gen
FROM [silver].[crm_cust_info] AS ci
LEFT JOIN [silver].[erp_cust_az12] AS ca
ON ci.cst_key = ca.cid
LEFT JOIN [silver].[erp_loc_a101] AS la
ON ci.cst_key = la.cid
ORDER BY 1,2

Select distinct gender from gold.dim_customers

Select prd_key, COUNT(*)
FROM
(
SELECT [prd_id]
      ,[cat_id]
      ,[prd_key]
      ,[prd_nm]
      ,[prd_cost]
      ,[prd_line]
      ,[prd_start_dt]
      ,pc.cat
      ,pc.subcat
      ,pc.maintenance
  FROM [DataWarehouse].[silver].[crm_prd_info] pn
  LEFT JOIN [silver].[erp_px_cat_g1v2] pc
  ON (pn.cat_id = pc.id)
  WHERE [prd_end_dt] IS NULL -- Filter out all historical data
  )t
  GROUP BY prd_key
  HAVING COUNT(*) > 1


  SELECT *
  FROM gold.fact_sales f
  LEFT JOIN gold.dim_customers c
  ON (c.customer_key = f.customer_key)
  Where c.customer_key is null


    SELECT *
  FROM gold.fact_sales f
  LEFT JOIN gold.dim_customers c
  ON (c.customer_key = f.customer_key)
  LEFT JOIN gold.dim_products p
  ON (p.product_key = f.product_key)
  Where c.customer_key is null or p.product_key is null
