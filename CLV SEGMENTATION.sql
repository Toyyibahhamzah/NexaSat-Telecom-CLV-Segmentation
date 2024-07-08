--create table
CREATE TABLE NexaSat_data (
    Customer_ID VARCHAR(50),
    gender VARCHAR(10),
    Partner VARCHAR(3),
    Dependents VARCHAR(3),
    Senior_Citizen INT,
    Call_Duration INT,
    Data_Usage FLOAT,
    Plan_Type VARCHAR(20),
    Plan_Level VARCHAR(20),
    Monthly_Bill_Amount FLOAT,
    Tenure_Months INT,
    Multiple_Lines VARCHAR(3),
    Tech_Support VARCHAR(3),
    Churn INT);

--Confirm current schema
SELECT CURRENT_SCHEMA();

--set path for queries
SET search_path TO "Nexa_Sat";

--view data
SELECT * FROM nexasat_data;

--Data Cleaning
--Check for duplicates (this filter out rows that are duplicates)
SELECT Customer_ID, gender, Partner, Dependents,
	Senior_Citizen, Call_Duration, Data_Usage, 
	Plan_Type, Plan_Level, Monthly_Bill_Amount,
	Tenure_Months, Multiple_Lines, Tech_Support,
	Churn
FROM nexasat_data
group by Customer_ID, gender, Partner, Dependents,
	Senior_Citizen, Call_Duration, Data_Usage, 
	Plan_Type, Plan_Level, Monthly_Bill_Amount,
	Tenure_Months, Multiple_Lines, Tech_Support,
	Churn
HAVING count (*) > 1;

--Checking for NULL Values
SELECT *
FROM nexasat_data
where Customer_ID is null 
or gender is null 
or Partner is null 
or Dependents is null
or Senior_Citizen is null 
or Call_Duration is null 
or Data_Usage is null 
or Plan_Type is null 
or Plan_Level is null 
or Monthly_Bill_Amount is null
or Tenure_Months is null 
or Multiple_Lines is null 
or Tech_Support is null
or Churn is null;

--EDA
--Total no of users
SELECT count(customer_id) AS Total_users 
from nexasat_data 
where churn = 0;

--Total user by level
select plan_level, count(customer_id) as total_users 
from nexasat_data 
WHERE churn = 0 
group by 1;

--total revenue
select to_char(round(sum(monthly_bill_amount::numeric),2), 'FM999,999,999,999.00') as Total_Revenue
from nexasat_data;

--revenue by plan level
SELECT plan_level, to_char(round(sum(monthly_bill_amount::numeric), 2), 'FM999,999,999,999.00') AS Revenue
FROM nexasat_data
GROUP BY plan_level
ORDER BY Revenue;

--churn count by plan type and plan level
SELECT plan_level, plan_type,
count (*) as Total_Customer,
sum(churn) as Churn_Count
from nexasat_data
group by 1, 2
order by 1;

--Average tenure by plan level
SELECT plan_level, round(avg(tenure_months::numeric), 2) as avg_tenure
from nexasat_data
group by 1;


--MARKETING SEGMENTS
--create table of existing users only
CREATE TABLE existing_users AS
select * 
from nexasat_data
where churn = 0;

--view new table
select *
from existing_users;

SELECT * FROM "Nexa_Sat".existing_users;

--view schema
SELECT current_schema();

--set path to nexa.sat
set search_path to "Nexa_Sat";

--Calculate ARPU for existing users
SELECT Round(avg(monthly_bill_amount::INT),2) as ARPU
from existing_users;


--Calculate CLV and add column
ALTER TABLE existing_users
ADD COLUMN CLV FLOAT;

UPDATE existing_users
SET CLV = monthly_bill_amount * tenure_months;

--view CLV column
SELECT customer_id, clv
FROM existing_users;

--clv score
--monthly_bill = 40%, tenure = 30%, call_duration = 10%, data_usage = 10%, premium = 10%
ALTER TABLE existing_users
ADD column clv_score numeric(10,2);

update existing_users
SET clv_score = 
			(0.4 * monthly_bill_amount) +
			(0.3 * tenure_months) +
			(0.1 * call_duration) +
			(0.1 * data_usage) +
			(0.1 * case when plan_level = 'premium'
					then 1 else 0
					end);

--view new clv score column
SELECT customer_id, clv_score
from existing_users;

alter table existing_users
add column clv_segments varchar;

--group users into segments based on clv_scores
ALTER TABLE existing_users
ADD column clv_segments VARCHAR;

UPDATE existing_users
SET clv_segments =
			case when clv_score > (SELECT percentile_cont(0.85)
								  within group (order by clv_score)
								  from existing_users) THEN 'High Value'
				when clv_score >= (SELECT percentile_cont(0.50)
								  within group (order by clv_score)
								  from existing_users) THEN 'Moderate Value'
				when clv_score >= (SELECT percentile_cont(0.25)
								  within group (order by clv_score)
								  from existing_users) THEN 'Low Value'
				ELSE 'Churn Risk'
				end;
			
			
--view segments
select customer_id, clv, clv_score, clv_segments
from existing_users;


--Analyzing the segment
--avg bill and tenure per segment
SELECT clv_segments,
		round(avg(monthly_bill_amount::int), 2) as avg_mothly_charges,
		round(avg(tenure_months::int), 2) as avg_tenure
FROM existing_users
group by 1;

--tech support and multiple lines count
select clv_segments,
		round(avg(case when tech_support = 'Yes' then 1 else 0 end), 2) as tech_support_pct,
		round(avg(case when multiple_lines = 'Yes' then 1 else 0 end), 2) as multiple_lines_pct
from existing_users
group by 1;


--revenue per segment
select clv_segments, count(customer_id),
		to_char(cast(sum(monthly_bill_amount * tenure_months) as numeric(10,2)), 'FM999,999,999,999.00') as revenue
from existing_users
group by 1;



--Cross-selling and up-selling
--Cross_selling tech support to snr citizens
SELECT customer_id
from existing_users
where senior_citizen = 1 --senior citizen
and dependents = 'No' --No of Children or tech savvy helpers
and tech_support = 'No' --do not already have this service
and (clv_segments = 'Churn Risk' or clv_segments = 'Low Value');

--cross-selling for: multiples lines for partners and dependents
select customer_id
from existing_users
where multiple_lines = 'No'
and(dependents = 'Yes' or partner = 'Yes')
and plan_level = 'Basic';

--up-selling: premium discount for basic users with churn risk
SELECT customer_id
from existing_users
where clv_segments = 'Churn Risk'
and plan_level = 'Basic';


--up-selling: basic to premium for longer lock in period and higher ARPU
SELECT plan_level, round(avg(monthly_bill_amount::int),2) as avg_bill, round(avg(tenure_months::int),2) as avg_tenure
from existing_users
where clv_segments = 'High Value'
or clv_segments = 'Moderate Value'
group by 1;

--select customers
select customer_id, monthly_bill_amount
from existing_users
where plan_level = 'Basic'
and (clv_segments = 'High Value' or clv_segments = 'Moderate Value')
and monthly_bill_amount > 150;

--create stored procedures
--snr citizens who will be offered tech support
CREATE FUNCTION tech_support_snr_citizens()
returns table (customer_id varchar(50))
as $$
BEGIN
	return query
	select eu.customer_id
	from existing_users eu
	where eu.senior_citizen = 1 --senior citizens
	and eu.dependents = 'No' --no children or tech savvy helpers
	and eu.tech_support = 'No' --do not already have this service
	and (eu.clv_segments = 'Churn Risk' or eu.clv_segments = 'Low Value');
end;
$$ LANGUAGE plpgsql;


--multiples lines for partners and dependents
CREATE FUNCTION multiple_lines_partners_dependents()
returns table (customer_id varchar(50))
as $$
BEGIN
	return query
	select eu.customer_id
	from existing_users eu
	where eu.multiple_lines = 'No'
	and(eu.dependents = 'Yes' or eu.partner = 'Yes')
	and eu.plan_level = 'Basic';
end;
$$ language plpgsql;

--at risk customers who will be offered premium discount
create function churn_risk_discount()
returns table (customer_id varchar(50))
as $$
BEGIN
	return query
	SELECT eu.customer_id
	from existing_users eu
	where eu.clv_segments = 'Churn Risk'
	and eu.plan_level = 'Basic';
end;
$$ language plpgsql;


--high usage customers who will be offered premium upgrade
CREATE function high_usage_basic()
returns table (customer_id varchar(50))
as $$
BEGIN
	return query
	select eu.customer_id
	from existing_users eu
	where eu.plan_level = 'Basic'
	and (eu.clv_segments = 'High Value' or eu.clv_segments = 'Moderate Value')
	and eu.monthly_bill_amount > 150;
end;
$$ language plpgsql;
--basic to premium for longer lock in period and higher ARPU
CREATE FUNCTION avg_bill_tenure_comparism()
returns table (plan_level varchar(50),avg_bill numeric,avg_tenure numeric)
as $$
BEGIN
	return query
	SELECT eu.plan_level, 
	round(avg(eu.monthly_bill_amount::int),2) as avg_bill, round(avg(eu.tenure_months::int),2) as avg_tenure
	from existing_users eu
	where eu.clv_segments = 'High Value'
	or eu.clv_segments = 'Moderate Value'
	group by 1;
end;
$$ language plpgsql;


--Use Procedures
--churn risk discount
select *
from churn_risk_discount();


--tech support snr citizens
select *
from tech_support_snr_citizens();

--multiple lines for partners and dependents
SELECT *
from multiple_lines_partners_dependents();


-- basic high usage customers
select *
from high_usage_basic();

--avg_bill and avg_tenure of basic & premium users
SELECT *
from avg_bill_tenure_comparism();
