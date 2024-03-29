/*
Ian Matlak
Implementaion
*/
--------------------------------------------------------------------------------------------------------------------------------------------------------
/*
TEST CASE 1

Stored Procedure spCreateAccount is used to help grab information from 
the user and create a user record for them within the database.
This Stored Procedure has 12 parameters which will contain the users info.
*/

CREATE PROC spCreateAccount
--ADDRESS
@ZipCode int,
@Country char(20),
@State char(20),
@Address char(20),

--PAYMENT
@CardType varchar(20),
@CardNumber varchar(16),
@CardHolder char(25),
@CVVNumber char(4),
@ExpirationDate char(10),

--Customer
@Email varchar(35),
@FirstName char(20),
@LastName char(20)
AS
Begin
Declare @AddressID int;
Declare @PaymentID int;

INSERT into tbl_opPAYMENT
VALUES(@CardType,@CardNumber,@CVVNumber,@ExpirationDate)

set @PaymentID = (Select @@IDENTITY)

INSERT into tbl_opADDRESS
VALUES(@ZipCode,@Country,@State,@Address)

set @AddressID = (Select @@IDENTITY)

INSERT into tbl_opCUSTOMER
VALUES(@Email, @AddressID, @PaymentID, @FirstName, @LastName, @ExpirationDate)

end
-------------------------------------------------------------------------------------------------------------------------------------
/*
TEST CASE 2

This Stored Procedure spOrderDetailsTotal is used when a customer
orders a product. It will first check that the information they typed in
is valid(customerID, ProductID, Quantity) It also check to make sure there
is an Order recored created for the user, if not it will create one automatically.
It will also insert the order they purchased into the shipping table.
It will check to see if there latest order is already added to the shipping table,
if so it will no re-add there orderID 
It also makes it so the customer cannot buy more then whats available in stock. It checks this by using an if statement.

Once this Stored Procedure is executed a trigger will lauch. This trigger contains two
Update functions that update the total price of the customers order and the inventory about
for the products that were purchased.
 
*/
alter PROC spOrderDetailsTotal --for purchasing products
	@CustID INT,
	@ProdNm varchar(20),
	@Quanity INT

	AS
	BEGIN
	Declare @ProdID as INT
	SET @ProdID = (select ProductID from tbl_opPRODUCT where ProductName = @ProdNM)
	IF EXISTS (Select count(*) from tbl_opCustomer cu  where cu.CustomerID = @CustID)
				IF EXISTS (Select count(*) from tbl_opPRODUCT where ProductID = @ProdID and InStock > @Quanity)
	
				--SELECT * FROM tbl_opPRODUCT,tbl_opCustomer cu
				--inner join tbl_opORDER ord
				--ON ord.OrderID = cu.CustomerID
				--WHERE cu.CustomerID = @CustID and ProductID = @ProdID and InStock > @Quanity
				
			BEGIN
				DECLARE @total FLOAT
				DECLARE @RecentOrderID INT
				DECLARE @Shipping INT

				SET @total = dbo.fnGetTotal(@ProdID, @Quanity);		--(SELECT (@Quanity * Price) FROM tbl_opPRODUCT pr
										--WHERE pr.ProductID = @ProdID and InStock > @Quanity)--CHANGE TO FUNCTION

				SET @RecentOrderID = (SELECT OrderID FROM tbl_opORDER ord
										inner join tbl_opCUSTOMER cu
										ON cu.CustomerID = ord.CustomerID
										WHERE ord.OrderDate = (SELECT max(OrderDate) FROM tbl_opORDER where CustomerID = @CustID) and cu.CustomerID = @CustID
										GROUP BY OrderID)

				IF @RecentOrderID is NULL
					BEGIN
						INSERT into tbl_opORDER
						VALUES(@CustID, GETDATE(), 0);

						SET @RecentOrderID = (SELECT OrderID FROM tbl_opORDER ord
										inner join tbl_opCUSTOMER cu
										ON cu.CustomerID = ord.CustomerID
										WHERE ord.OrderDate = (SELECT max(OrderDate) FROM tbl_opORDER where CustomerID = @CustID) and cu.CustomerID = @CustID
										GROUP BY OrderID)

						INSERT into tbl_opORDERDETAILS
						VALUES(@ProdID, @RecentOrderID, @Quanity, @total);
					END;
				ELSE
					BEGIN
						SET @RecentOrderID = (SELECT OrderID FROM tbl_opORDER ord
										inner join tbl_opCUSTOMER cu
										ON cu.CustomerID = ord.CustomerID
										WHERE ord.OrderDate = (SELECT max(OrderDate) FROM tbl_opORDER where CustomerID = @CustID) and cu.CustomerID = @CustID
										GROUP BY OrderID)

						INSERT INTO tbl_opORDERDETAILS
						VALUES(@ProdID, @RecentOrderID, @Quanity, @total);
					END;
						
				SET @Shipping = (select OrderID from tbl_opSHIPPING where OrderID = @RecentOrderID)

				IF @Shipping is NULL
					BEGIN
						Print('Shipping  NULL')

						INSERT INTO tbl_opSHIPPING(OrderID, ShippingCompany)
						VALUES(@RecentOrderID, 'FedEx');
					END;
				ELSE
					BEGIN
						Print('Shipping already set')
					END;

			END;
	ELSE
		If @ProdID != (SELECT COUNT(ProductID) FROM tbl_opPRODUCT
						WHERE ProductID = @ProdID)
			BEGIN
					Print('That Product doesnt not exist')
			END
		ELSE
			IF @Quanity > (SELECT COUNT(InStock) FROM tbl_opPRODUCT
								WHERE ProductID = 1 and @Quanity < InStock)
			BEGIN
					--NEEDS TO BE TESTED/alter table
					--UPDATE tbl_opPRODUCT 
					--SET InStock = InStock - @Quanity
					--WHERE ProductID = @ProdID
					Print('Your Quanitity is to high or we are sold out')
			END
		ELSE
					Print('You need to use a valid customerID')
	END
-----------------------------------------------------------------------------------------------------------------------------------------------------------------
/*
TEST CASE 3

This is the trigger that is fired when spOrderDetailsTotal is executed. It calculated the total cost
of the customers selected items and also updated the stock which was minus when the customer buys it.

See Test Case 2 for more information. 
*/
ALTER TRIGGER tOrderDetails_INSERT
ON tbl_opORDERDETAILS
AFTER INSERT
AS
	UPDATE tbl_opORDER
	SET
		TotalCost = (Select (SUM(Total)) from tbl_opORDERDETAILS where OrderID = (select orderid from inserted)) --where new record made
		where OrderID = (select OrderID from inserted)

	UPDATE tbl_opPRODUCT
	SET
		InStock = (Select InStock from tbl_opPRODUCT where ProductID = (select ProductID from inserted)) - (select Quantity from tbl_opORDERDETAILS where OrderDetailsID = (select OrderDetailsID from inserted))
		where ProductID = (select ProductID from inserted)

----------------------------------------------------------------------------------------------------------------------------------------------------------------------
/*
TEST CASE 4

This Trigger is fired when a new order is updated. Once updated this trigger updates the virtual invoice table which
then provides a total with tax and other details for the customer to see.

See Test Case 3 for more information. 
*/
ALTER TRIGGER tOrder_UPDATE
ON tbl_opORDER
AFTER UPDATE
AS
	insert tbl_opVIRTUALINVOICE
	Values((select orderid from inserted), (Select (TotalCost*0.086) + TotalCost from tbl_opORDER where OrderID = (select orderid from inserted)), 0.086, GETDATE())
		
----------------------------------------------------------------------------------------------------------------------------------------------------------------------
ALTER FUNCTION fnGetTotal (@ProdID int, @Quanity int)
	RETURNS Float
Begin
	Return (SELECT (@Quanity * Price) FROM tbl_opPRODUCT pr
								WHERE pr.ProductID = @ProdID and InStock > @Quanity)
END;
---------------------------------------------------------------------------------------------------------------------------------------------------------------------
/*
TEST CASE 5

This View is created for customers to see a list of the products that are available.
It shows Product Names, Price, Model Numbers, Descritions of warrrenty, type of item and
how many of them are in stock.
*/
CREATE VIEW vProductList as
select ProductName,Price,ModelNumber,Description,Type,InStock
from tbl_opPRODUCT pr
inner join tbl_opPRODUCTCATEGORIES prc
on pr.ProductCategoryID = prc.ProductCategoryID
inner join tbl_opWARRANTY wr
on wr.WarrantyID = 1
where Instock != 0
