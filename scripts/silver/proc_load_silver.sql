/*
===============================================================================================
Stored Procedure: Load Silver layer (Bronze -> Silver)
===============================================================================================
Script Purpose:
		This stored procedure performs the ETL process to populate from the 'bronze' schema into the 'silver' schema.
It performs the following actions:
		- Truncate the silver tables before loading data
		- Transform and massage the data on the bronze tables
		- Insert the transofrmed data from the bronze into the silver tables

Parameters:
	None.
	This stored procedure does not accept any parameters or return any values.

Usage Example:
	EXEC silver.load_silver
===============================================================================================
*/

CREATE OR ALTER PROCEDURE silver.load_silver AS
BEGIN
	DECLARE @start_time DATETIME, @end_time DATETIME, @batch_start_time DATETIME, @batch_end_time DATETIME;
	BEGIN TRY

		SET @batch_start_time = GETDATE();
		PRINT '====================================================================';
		PRINT 'Loading Silver Layer';
		PRINT '====================================================================';

		PRINT '--------------------------------------------------------------------';
		PRINT ' Loading CRM Tables'
		PRINT '--------------------------------------------------------------------';

		PRINT '>> Truncate Table: silver.crm_cust_info';
		TRUNCATE TABLE silver.crm_cust_info;
		PRINT '>> Inserting Date Into: silver.crm_cust_info';
		SET @start_time = GETDATE();

		INSERT INTO silver.crm_cust_info
		(
		cst_id,
		cst_key,
		cst_firstname,
		cst_lastname,
		cst_marital_status,
		cst_gndr,
		cst_create_date
		)
		SELECT
		cst_id,
		cst_key,
		TRIM(cst_firstname), -- Trim first name (remove white spaces)
		TRIM(cst_lastname), -- Trim last name (remove white spaces).
		CASE	WHEN UPPER(cst_marital_status) = 'S' THEN 'Single' -- Normalize marital status values and handle unknown cases
				WHEN UPPER(cst_marital_status) = 'M' THEN 'Married'
				ELSE 'n/a'
		END cst_marital_status,
		CASE	WHEN UPPER(cst_gndr) = 'M' THEN 'Male' -- Normalize gender values and handle unknown cases
				WHEN UPPER(cst_gndr) = 'F' THEN 'Female'
				ELSE 'n/a'
		END cst_gndr,
		cst_create_date
		from (
			SELECT *, 
			ROW_NUMBER () OVER (PARTITION BY cst_id ORDER BY cst_create_date ASC) flag -- Grab only the active customer info by ordering cst_id by cst_create_date in window function ROW_NUMBER ()
			  FROM [DataWarehouse].[bronze].[crm_cust_info]
			  Where cst_id IS NOT NULL
		) t
		WHERE flag = 1

		SET @end_time = GETDATE();
		PRINT '>> Load Duration: ' + CAST(DATEDIFF(second,@start_time,@end_time) AS NVARCHAR) + ' seconds';
		PRINT '>> -------------------';

--------------------------------------------------------------------------------------------------------------------------------------------------------
		
		PRINT '>> Truncate Table: silver.crm_prd_info';
		TRUNCATE TABLE silver.crm_prd_info;
		PRINT '>> Inserting Date Into: silver.crm_prd_info';
		SET @start_time = GETDATE();

		INSERT INTO silver.crm_prd_info(
		 [prd_id],
		 cat_id,
		 prd_key,
		 [prd_nm],
		 prd_cost,
		 [prd_line],
		 [prd_start_dt],
		 [prd_end_dt]
		)

		SELECT [prd_id]
			  ,REPLACE(SUBSTRING([prd_key],1,5),'-','_') AS cat_id -- Normalize cat_id column so that we can join with erp_px_cat_g1v2 table
			  ,SUBSTRING([prd_key],7, LEN([prd_key])) AS prd_key -- Normalize prd_key so that we can join with crm_sales_details table
			  ,[prd_nm]
			  ,ISNULL([prd_cost],0) AS prd_cost -- Cost can't be NULL convert to 0
			  ,CASE UPPER(TRIM([prd_line])) -- Normalize the prd_line data
					WHEN 'M' THEN 'Moustain'
					WHEN 'R' THEN 'Road'
					WHEN 'S' THEN 'Other Sales'
					WHEN 'T' THEN 'Touring'
					ELSE 'N/A'
			   END AS prd_line
			  ,CAST([prd_start_dt] as DATE)
			  ,CAST(LEAD (prd_start_dt) OVER (PARTITION BY [prd_key] ORDER BY prd_start_dt)-1 AS DATE) AS [prd_end_dt] -- Calculate appropriate end date based off the lead start date
		FROM [DataWarehouse].[bronze].[crm_prd_info]

		SET @end_time = GETDATE();
		PRINT '>> Load Duration: ' + CAST(DATEDIFF(second,@start_time,@end_time) AS NVARCHAR) + ' seconds';
		PRINT '------------------';

-------------------------------------------------------------------------------------------------------------------------------------------------------
		
		PRINT '----------------------------------------------------------------------';
		PRINT 'Loading ERP Tables';
		PRINT '----------------------------------------------------------------------';

		PRINT '>> Truncate Table: silver.crm_sales_details';
		TRUNCATE TABLE silver.crm_sales_details;
		PRINT '>> Inserting Date Into: silver.crm_sales_details';
		SET @start_time = GETDATE();

		INSERT INTO silver.crm_sales_details(
			sls_ord_num,
			sls_prd_key,
			sls_cust_id,
			sls_order_dt,
			sls_ship_dt,
			sls_due_dt,
			sls_sales,
			sls_quantity,
			sls_price
		)
		SELECT [sls_ord_num]
			  ,[sls_prd_key]
			  ,[sls_cust_id]
			  ,CASE WHEN [sls_order_dt] = 0 OR LEN(sls_order_dt) != 8 THEN NULL -- Normalize sls_order_dt to accept only valid values and cast to date
					ELSE CAST(CAST(sls_order_dt AS VARCHAR) AS DATE)
			   END AS  sls_order_dt
			  ,CASE WHEN [sls_ship_dt] = 0 OR LEN([sls_ship_dt]) != 8 THEN NULL -- Normalize sls_ship_dt to accept only valid values and cast to date
					ELSE CAST(CAST([sls_ship_dt] AS VARCHAR) AS DATE)
			   END AS  [sls_ship_dt]
			  ,CASE WHEN [sls_due_dt] = 0 OR LEN([sls_due_dt]) != 8 THEN NULL -- Normalize sls_due_dt to accept only valid values and cast to date
					ELSE CAST(CAST([sls_due_dt] AS VARCHAR) AS DATE)
			   END AS  [sls_due_dt]
			  ,CASE	WHEN sls_sales IS NULL OR sls_sales <= 0 OR sls_sales != sls_quantity * ABS(sls_price) -- Calculate total revenue correctly from the sls_quantity * sls_price
					THEN sls_quantity * ABS(sls_price)
					ELSE sls_sales
				END AS sls_sales
			  ,[sls_quantity]
			  ,CASE	WHEN sls_price IS NULL OR sls_price <= 0 -- Calculate the sale price by deviding total revenue by the quantity
					THEN sls_sales / NULLIF(sls_quantity,0)
					ELSE sls_price
				END AS sls_price
		  FROM [DataWarehouse].[bronze].[crm_sales_details]
		  
		  SET @end_time = GETDATE();
		  PRINT '>> Load Duration: ' + CAST(DATEDIFF(second,@start_time,@end_time) AS NVARCHAR) + ' seconds';
		  PRINT '------------------';

-----------------------------------------------------------------------------------------------------------------------------------------------------------------

		PRINT '>> Truncate Table: silver.silver.erp_cust_az12';
		TRUNCATE TABLE silver.erp_cust_az12;
		PRINT '>> Inserting Date Into: silver.erp_cust_az12';
		SET @start_time = GETDATE();

		INSERT INTO silver.erp_cust_az12 (cid,bdate,gen)
		SELECT 
		CASE	WHEN cid like 'NAS%' --Remove 'NAS' prefix if present
				THEN SUBSTRING(cid,4,len(cid)) 
				ELSE cid
		END as cid,
		CASE	WHEN bdate > GETDATE() THEN NULL -- Set future birthdates to NULL
				ELSE bdate
		END AS bdate,
		CASE	WHEN UPPER(TRIM(gen)) in ('M','MALE') THEN 'Male' -- Normalize gender values and handle unknown cases
				WHEN UPPER(TRIM(gen)) in ('F','FEMALE') THEN 'Female'
				ELSE 'N/A'
		END AS gen
		FROM bronze.erp_cust_az12
		
		SET @end_time = GETDATE();
		PRINT '>> Load Duration: ' + CAST(DATEDIFF(second,@start_time,@end_time) as NVARCHAR) + ' seconds';
		PRINT '------------------';

------------------------------------------------------------------------------------------------------------------------------------------------------------------

		
		PRINT '>> Truncate Table: silver.erp_loc_a101';
		TRUNCATE TABLE silver.erp_loc_a101;
		PRINT '>> Inserting Date Into: silver.erp_loc_a101';
		SET @start_time = GETDATE();

		INSERT INTO silver.erp_loc_a101(
		cid,
		cntry
		)
		SELECT
		REPLACE(TRIM(cid),'-','') AS cid, -- Make the cid key be able to join with the crm_cust_info table
		CASE	WHEN TRIM(cntry) = 'DE' THEN 'Germany' -- Normalization of the cntry data based on abbreviations and handle missing or blank country codes
				WHEN TRIM(cntry) in ('USA','US') THEN 'United States'
				WHEN TRIM(cntry) = '' or TRIM(cntry) IS NULL THEN 'N/A'
				ELSE TRIM(cntry)
		END as cntry
		FROM [bronze].[erp_loc_a101]
		
		SET @end_time = GETDATE();
		PRINT '>> Load Duration: ' + CAST(DATEDIFF(second,@start_time,@end_time) as NVARCHAR) + ' seconds';
		PRINT '------------------';

		--------------------------------------------------------------------------------------------------------------------------------------------------------------------

		PRINT '>> Truncate Table: silver.erp_px_cat_g1v2';
		TRUNCATE TABLE silver.erp_px_cat_g1v2;
		PRINT '>> Inserting Date Into: silver.erp_px_cat_g1v2';
		SET @start_time = GETDATE()

		INSERT INTO silver.erp_px_cat_g1v2
		(
		id,
		cat,
		subcat,
		maintenance
		)
		SELECT
		id,
		cat,
		subcat,
		maintenance
		FROM [bronze].[erp_px_cat_g1v2]

		SET @end_time = GETDATE();
		PRINT '>> Load Duration: ' + CAST(DATEDIFF(second,@start_time,@end_time) as NVARCHAR) + ' seconds';
		PRINT '------------------';

----------------------------------------------------------------------------------------------------------------------------------------------------------------------
		
		SET @batch_end_time = GETDATE();
		PRINT '======================================';
		PRINT 'Loading Silver Layer is Completed';
		PRINT ' - Total Load Duration: ' + CAST(DATEDIFF(SECOND,@batch_start_time,@batch_end_time) AS NVARCHAR) + ' seconds';
		PRINT '======================================';

	END TRY
	BEGIN CATCH

		PRINT  '=====================================================================';
		PRINT  'AN ERROR OCCURED LOADING THE SILVER LAYER!'; 
		PRINT  '=====================================================================';
		PRINT 'Error Message: ' + ERROR_MESSAGE();
		PRINT 'Error Number: ' + CAST(ERROR_NUMBER() AS NVARCHAR);
		PRINT 'Error Message: ' + CAST(ERROR_STATE() AS NVARCHAR);

	END CATCH
END
