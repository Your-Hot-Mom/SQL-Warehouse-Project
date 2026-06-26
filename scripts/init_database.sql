/*

======================================================================================
Create Database and Schemas
======================================================================================
Script Purpose:
	This script creates a new database named 'DataWarehouse' after checking if it already exists.
	If the database exists, it is dropped and recreated. Additionally, the script sets up three schemas within the databas: bronze, silver, and gold.

WARNING:
Running this script will drop the entire 'DataWarehouse' database if it exists.
All data in the database will be permanently deleted. Proceed with caution and ensure you have proper backups before running this script.

*/

USE MASTER;
GO
IF EXISTS (SELECT 1 FROM sys.databases WHERE name = 'DataWarehouse')
BEGIN
	ALTER DATABASE DataWarehouse SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
	DROP DATABASE DataWarehouse
END;
go

--Create the 'DataWarehouse' database
create database DataWarehouse;
go

Use [DataWarehouse];
go

--Create the Schemas
create schema bronze;
go

create schema silver;
go

create schema gold;

