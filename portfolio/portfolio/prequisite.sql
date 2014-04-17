CREATE TABLE Users(
	UserID Integer NOT NULL,
	LastName varchar2(255) NOT NULL,
	FirstName varchar2(255),
	Email varchar2(255) NOT NULL UNIQUE,
	Password varchar2(255) NOT NULL,
	PRIMARY KEY (UserID)
);

CREATE TABLE Portfolios(
	PortfolioID Integer NOT NULL,
	PortfolioName varchar(255) NOT NULL,
	UserID Integer REFERENCES Users(UserID),
	Cash Integer NOT NULL,
	PRIMARY KEY (PortfolioID)
);

CREATE TABLE Holdings(
	PortfolioID Integer Not NULL REFERENCES Portfolios(PortfolioID),
	Symbol varchar2(10) NOT NULL,
	Shares NUMBER(10) NOT NULL,
	PRIMARY KEY(PortfolioID, Symbol)
); 

CREATE TABLE StocksDailyNew(
	SYMBOL varchar2(16) NOT NULL,
	TIMESTAMP NUMBER NOT NULL,
	OPEN NUMBER NOT NULL,
	HIGH NUMBER NOT NULL,
	LOW NUMBER NOT NULL,
	CLOSE NUMBER NOT NULL,
	VOLUME NUMBER NOT NULL,
	PRIMARY KEY (SYMBOL, TIMESTAMP)
);

CREATE TABLE Transactions(
	PortfolioID Integer NOT NULL,
	TimeStamp NUMBER NOT NULL,
	Symbol VARCHAR2(10) NOT NULL,
	TransactionType VARCHAR2(4) NOT NULL CHECK (TransactionType = 'Buy' OR TransactionType = 'Sell'),
	Shares NUMBER NOT NULL,
	Price Integer,
	PRIMARY KEY (PortfolioID, TimeStamp)
);


-- 
-- create a sequence on USERID
--
CREATE SEQUENCE UserID
	MAXVALUE 999999999999999999999999999
	START WITH 1
	INCREMENT BY 1
	CACHE 50;
	
-- 
-- create a sequence on PortfolioID
--
CREATE SEQUENCE PortfolioID
	MAXVALUE 999999999999999999999999999
	START WITH 1
	INCREMENT BY 1
	CACHE 50;

--
-- create a trigger
--

CREATE OR REPLACE TRIGGER	auto_userid
	BEFORE INSERT ON Users
	FOR EACH ROW
BEGIN
	SELECT UserID.nextval
	INTO :new.UserID
	from dual;
END;
/

--
-- create a trigger
--

CREATE OR REPLACE TRIGGER auto_portfolioid
	BEFORE INSERT ON Portfolios
	FOR EACH ROW
BEGIN
	SELECT PortfolioID.nextval
	INTO :new.PortfolioID
	from dual;
END;
/

