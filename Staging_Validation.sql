

USE 'My_DB'
GO

/****** Object:  Table [validation].[STAGING_DATE_VALIDATION_DATE_TYPE]    Script Date: 30.1.2020 15.33.59 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [validation].[STAGING_DATE_VALIDATION_DATE_TYPE](
	[Date_Column_Type] [int] NOT NULL,
	[Date_Column_Format] [varchar](32) NOT NULL,
 CONSTRAINT [PK_STAGING_DATE_VALIDATION_DATE_TYPE] PRIMARY KEY CLUSTERED 
(
	[Date_Column_Type] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]
GO






/****** Object:  Table [validation].[STAGING_DATE_VALIDATION]    Script Date: 30.1.2020 15.33.01 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [validation].[STAGING_DATE_VALIDATION](
	[Table_Name] [varchar](256) NOT NULL,
	[Date_Column_Name] [varchar](256) NOT NULL,
	[Date_Column_Type] [int] NULL,
	[Validate_Staging_Rows] [int] NULL,
	[Table_Schema] [varchar](8) NULL,
 CONSTRAINT [PK_STAGING_DATE_VALIDATION] PRIMARY KEY CLUSTERED 
(
	[Table_Name] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]
GO

ALTER TABLE [validation].[STAGING_DATE_VALIDATION]  WITH CHECK ADD  CONSTRAINT [FK_STAGING_DATE_VALIDATION_TYPE] FOREIGN KEY([Date_Column_Type])
REFERENCES [validation].[STAGING_DATE_VALIDATION_DATE_TYPE] ([Date_Column_Type])
GO

ALTER TABLE [validation].[STAGING_DATE_VALIDATION] CHECK CONSTRAINT [FK_STAGING_DATE_VALIDATION_TYPE]
GO




/****** Object:  StoredProcedure [validation].[P_VALIDATE_STAGING_DATE_COLUMNS]    Script Date: 29.1.2020 9.21.35 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


-- =============================================
-- Author:		Valter Prykäri
-- 
-- Description:	Procedure to check date columns in staging tables, uses [validation].[STAGING_DATE_VALIDATION]-table to control tables and date columns
-- Uses previous bank day from calendar for correct date validation
-- =============================================

CREATE PROCEDURE [validation].[P_VALIDATE_STAGING_DATE_COLUMNS]
AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	DECLARE @table varchar(64)
	,@sql nvarchar(256)
	,@column  varchar(64)
	,@schema  varchar(8)
	,@format  varchar(64)
	,@errormsg varchar(5000)
	,@tablelist varchar(5000) = ''
	,@bankday int  
	
	--get previous bank day
	SET @bankday = (SELECT max(c.DateKey) FROM [dbo].[CALENDAR] c	WHERE c.[Date]  < cast(GETDATE() as date)	AND c.Is_Bankday = 1)
	
	DROP TABLE if exists  #tables
	
	SELECT v.Table_Name,v.Date_Column_Name,t.Date_Column_Format,v.Table_Schema 
	INTO #tables
	FROM [validation].[STAGING_DATE_VALIDATION] v
	JOIN [validation].[STAGING_DATE_VALIDATION_DATE_TYPE] t
	ON v.Date_Column_Type = t.Date_Column_Type
	
	DROP TABLE if exists  #validation 

	CREATE TABLE #validation
	(Table_Name varchar(64)
	,Report_Date_Format varchar(64)
	,Report_Date varchar(64)
	,Report_Date_Int int)
	
	--Loop through tables, pick distinct dates per table
	WHILE EXISTS (SELECT 1 FROM #tables)
	BEGIN
		SET @table = (SELECT TOP 1 Table_Name FROM #tables)
		SET @column = (SELECT TOP 1 Date_Column_Name FROM #tables WHERE Table_Name = @table)
		SET @format = (SELECT TOP 1 Date_Column_Format FROM #tables WHERE Table_Name = @table)
		SET @schema = (SELECT TOP 1 Table_Schema FROM #tables WHERE Table_Name = @table)

		SET @sql = 'INSERT INTO #validation (Table_Name, Report_Date_Format, Report_Date) SELECT DISTINCT ''' + @table +''', ''' + @format +''',' + @column + ' FROM [' + @schema + '].[' + @table + ']'
		BEGIN TRY
			EXEC sp_executesql @sql	
		END TRY
		BEGIN CATCH
			SET @errormsg = @table + ' is configured incorrectly for validation'
			RAISERROR(@errormsg,16,1)
		END CATCH
		
		BEGIN TRY
			--Convert report date to int based on formatting
			UPDATE #validation
			SET Report_Date_Int = CASE 
									WHEN Report_Date_Format = 'DD.MM.YYYY' THEN CAST(CONVERT(VARCHAR,CONVERT(date, Report_Date,104),112) AS INT)
									WHEN Report_Date_Format = 'DD.M.YYYY' THEN CAST(RIGHT(Report_Date,4)+RIGHT('0' + REPLACE(SUBSTRING(Report_Date,4,2),'.',''),2)+LEFT(Report_Date,2) AS INT)
									WHEN Report_Date_Format = 'Date, Import' THEN CAST(REPLACE(CAST(DATEADD(dd,-1,CAST(Report_Date as date)) as varchar(10)),'-','') as INT)
									WHEN Report_Date_Format = 'DD/MM/YYYY' THEN CAST(RIGHT(Report_Date,4)+SUBSTRING(Report_Date,4,2)+LEFT(Report_Date,2) AS INT)
									WHEN Report_Date_Format = 'Int' THEN Report_Date
									WHEN Report_Date_Format = 'Datetime' THEN CAST(REPLACE(CAST(CAST(Report_Date as Date) as Varchar(10)),'-','') as INT)
									WHEN Report_Date_Format = 'MM/DD/YYYY' THEN CAST(RIGHT(Report_Date,4)+LEFT(Report_Date,2)+SUBSTRING(Report_Date,4,2) AS INT)
									WHEN Report_Date_Format = 'MM.DD.YY' THEN CAST(RIGHT(Report_Date,2)+SUBSTRING(Report_Date,4,2)+LEFT(Report_Date,2) AS INT)
									WHEN Report_Date_Format = 'YYYY-MM-DD' THEN CAST(REPLACE(Report_Date, '-', '') as int)
									WHEN Report_Date_Format = 'DD.MM.YY' THEN cast(Replace( cast(CONVERT(date,  Report_Date, 3) as varchar(10)), '-', ''  ) as int)
									WHEN Report_Date_Format = 'DD-MM-YYYY' THEN cast(replace(cast(convert(date, convert(date, Report_Date, 105 ), 112) as varchar(15)), '-', '') as int)
									WHEN Report_Date_Format = '"DD/MM/YYYY"' THEN CAST(RIGHT(REPLACE(Report_Date,'"',''),4)+SUBSTRING(REPLACE(Report_Date,'"',''),4,2)+LEFT(REPLACE(Report_Date,'"',''),2) AS INT)
									ELSE NULL
							  END
			WHERE Table_Name = @table
		END TRY
		BEGIN CATCH
			SET @errormsg = 'Cannot convert date column to INT, table: ' + @table
			RAISERROR(@errormsg,16,1)
		END CATCH 

		DELETE FROM #tables WHERE Table_Name = @table
	END
	

	--select all error-tables into temp-table by testing against previous bank day

	DROP TABLE if exists  #error_tables

	
	SELECT DISTINCT v.Table_Name 
	INTO #error_tables
	FROM #validation v
	WHERE v.Report_Date_Int <> @bankday
	AND v.Report_Date_Int <> 0

	--raise error if there are error tables
	IF EXISTS (
	SELECT 1 FROM #error_tables)
	BEGIN

		--create list of tables and raise the error
		SELECT @tablelist = @tablelist + CAST(Table_Name AS VARCHAR(64)) +', ' from #error_tables
		SELECT @tablelist = SUBSTRING(@tablelist, 0, LEN(@tablelist)) --remove last comma
		SET @errormsg = 'Some dates are not correct in staging area, check for possible previous errors! Tables wih errors: ' + @tablelist
		RAISERROR(@errormsg,16,1)
	
	END
	
	--wipe mess
	DROP TABLE IF EXISTS #tables
	DROP TABLE IF EXISTS #validation
	DROP TABLE IF EXISTS #error_tables
END
GO


