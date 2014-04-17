#!/usr/bin/perl -w


#
# Debugging
#
# database input and output is paired into the two arrays noted
#
my $debug=0; # default - will be overriden by a form parameter or cookie
my @sqlinput=();
my @sqloutput=();

#
# The combination of -w and use strict enforces various 
# rules that make the script more resilient and easier to run
# as a CGI script.
#
use strict;

# The CGI web generation stuff
# This helps make it easy to generate active HTML content
# from Perl
#
# We'll use the "standard" procedural interface to CGI
# instead of the OO default interface
use CGI qw(:standard);


# The interface to the database.  The interface is essentially
# the same no matter what the backend database is.  
#
# DBI is the standard database interface for Perl. Other
# examples of such programatic interfaces are ODBC (C/C++) and JDBC (Java).
#
#
# This will also load DBD::Oracle which is the driver for
# Oracle.
use DBI;

#
#
# A module that makes it easy to parse relatively freeform
# date strings into the unix epoch time (seconds since 1970)
#
use Time::ParseDate;
use Finance::QuoteHist::Yahoo;
use Finance::Quote;
use Date::Manip;
use Getopt::Long;
use Data::Dumper;
use FileHandle;
use Time::Local;
use Time::CTime;
use stock_data_access;




BEGIN {
  $ENV{PORTF_DBMS}="oracle";
  $ENV{PORTF_DB}="cs339";
  $ENV{PORTF_DBUSER}="pdinda";
  $ENV{PORTF_DBPASS}="pdinda";

  unless ($ENV{BEGIN_BLOCK}) {
    use Cwd;
    $ENV{ORACLE_BASE}="/raid/oracle11g/app/oracle/product/11.2.0.1.0";
    $ENV{ORACLE_HOME}=$ENV{ORACLE_BASE}."/db_1";
    $ENV{ORACLE_SID}="CS339";
    $ENV{LD_LIBRARY_PATH}=$ENV{ORACLE_HOME}."/lib";
    $ENV{BEGIN_BLOCK} = 1;
    exec 'env',cwd().'/'.$0,@ARGV;
  }
};

#
# The session cookie will contain the user's name and password so that 
# he doesn't have to type it again and again. 
#
# "portfolioSession"=>"user/password"
#
# BOTH ARE UNENCRYPTED AND THE SCRIPT IS ALLOWED TO BE RUN OVER HTTP
# THIS IS FOR ILLUSTRATION PURPOSES.  IN REALITY YOU WOULD ENCRYPT THE COOKIE
# AND CONSIDER SUPPORTING ONLY HTTPS
#
my $cookiename="Session";
#
# And another cookie to preserve the debug state
#
my $debugcookiename="Debug";

#
# Get the session input and debug cookies, if any
#
my $inputcookiecontent = cookie($cookiename);
my $inputdebugcookiecontent = cookie($debugcookiename);

#
# Will be filled in as we process the cookies and paramters
#
my $outputcookiecontent = undef;
my $outputdebugcookiecontent = undef;
my $deletecookie=0;
my $userID = undef;
my $email = undef;
my $password = undef;
my $logincomplain=0;

#
# Get the user action and whether he just wants the form or wants us to
# run the form
#
my $action;
my $run;


if (defined(param("act"))) { 
  $action=param("act");
  if (defined(param("run"))) { 
    $run = param("run") == 1;
  } else {
    $run = 0;
  }
} else {
  $action="base";
  $run = 1;
}


if (defined(param("debug"))) { 
  # parameter has priority over cookie
  if (param("debug") == 0) { 
    $debug = 0;
  } else {
    $debug = 1;
  }
} else {
  if (defined($inputdebugcookiecontent)) { 
    $debug = $inputdebugcookiecontent;
  } else {
    # debug default from script
  }
}

$outputdebugcookiecontent=$debug;

#
#
# Who is this?  Use the cookie or anonymous credentials
#
#
if (defined($inputcookiecontent)) { 
  # Has cookie, let's decode it
  ($email,$password,$userID) = split(/\//,$inputcookiecontent);
  $outputcookiecontent = $inputcookiecontent;
}

#
# Is this a login request or attempt?
# Ignore cookies in this case.
#
if ($action eq "login") { 
  if ($run) { 
    #
    # Login attempt
    #
    # Ignore any input cookie.  Just validate user and
    # generate the right output cookie, if any.
    #
    ($email,$password) = (param('email'),param('passwd'));
		# ValidUser returns user ID if user exists, undef othwewise 
		my @row = ValidUser($email, $password);
		$userID = $row[0];
    if (defined($userID)) { 
      # if the user's info is OK, then give him a cookie
      # that contains his email and password 
      # the cookie will expire in one hour, forcing him to log in again
      # after one hour of inactivity.;
      # Also, land him in the base query screen
      $outputcookiecontent=join("/",$email,$password,$userID);
      $action = "base";
      $run = 1;
    } else {
      # uh oh.  Bogus login attempt.  Make him try again.
      # don't give him a cookie
      $logincomplain=1;
      $action="login";
      $run = 0;
    }
  } else {
    #
    # Just a login screen request, but we should toss out any cookie
    # we were given
    #
    undef $inputcookiecontent;
    ($userID,$password,$email)=(undef,undef,undef);
  }
} 


#
# If we are being asked to log out, then if 
# we have a cookie, we should delete it.
#
if ($action eq "logout") {
  $deletecookie=1;
  $action = "base";
  $userID = undef;
  $password = undef;
  $email = undef;
  $run = 1;
}


my @outputcookies;


#
# OK, so now we have user/password
# and we *may* have an output cookie.   If we have a cookie, we'll send it right 
# back to the user.
#
# We force the expiration date on the generated page to be immediate so
# that the browsers won't cache it.
#
if (defined($outputcookiecontent)) { 
  my $cookie=cookie(-name=>$cookiename,
		    -value=>$outputcookiecontent,
		    -expires=>($deletecookie ? '-1h' : '+1h'));
  push @outputcookies, $cookie;
} 
#
# We also send back a debug cookie
#
#
if (defined($outputdebugcookiecontent)) { 
  my $cookie=cookie(-name=>$debugcookiename,
		    -value=>$outputdebugcookiecontent);
  push @outputcookies, $cookie;
}

if ($action eq "port-new") {
	 print header(-type=>'image/png');
}else {
#
# Headers and cookies sent back to client
#
# The page immediately expires so that it will be refetched if the
# client ever needs to update it
#
print header(-expires=>'now', -cookie=>\@outputcookies);

#
# Now we finally begin generating back HTML
#
print "<html>";
print "<head>";
print "<title>Portfolio Management</title>";

# Include JQuery
#print "<script type=\"text/javascript\" src=\"./js/jquery-1.10.2.min.js\"></script>";

# import Twitter Bootstrap to pretty-ify things
#print "<link media=\"screen\" rel=\"stylesheet\" href=\"./bootstrap/css/bootstrap.min.css\">";
#print "<script type=\"text/javascript\" src=\"./bootstrap/js/bootstrap.min.js\"></script>";

print "</head>";

print "<body style=\"height:100\%;margin:0\">";
}
# GetPortfolios return a hash with structure: 
#     portfolioname => portfolioID
# in which name used for presentation and ID used to following operations.
#
my %portfolios = GetPortfolios($userID);

# LOGIN
#
# Login is a special case since we handled running the filled out form up above
# in the cookie-handling code.  So, here we only show the form if needed
# 
#
if ($action eq "login") { 
  print "<div style=\"text-align:center\">";
  if ($logincomplain) { 
    print "Login failed.  Try again.<p>"
  } 
  if ($logincomplain or !$run) { 
    print start_form(-name=>'Login'),
    h2('Login to use your portfolio'),
    "Email:",textfield(-name=>'email'),	p,
    "Password:",password_field(-name=>'passwd'),p,
    hidden(-name=>'act',default=>['login']),
    hidden(-name=>'run',default=>['1']),
    submit,
    end_form;
    print "<p>Not registered? <a href=\"portfolio.pl?act=sign-up\">Sign up here</a></p>";
  }
  print "</div>";
}


#
# BASE
#
# The base action presents the overall page to the browser
#
#
#
if ($action eq "base") { 
  if(!defined($email)) {
    print "<h2 class=\"page-title\">You are not signed in, but you can <a href=\"portfolio.pl?act=login\">login</a></h2>";
  } else {
    print "<h2 class=\"page-title\">Welcome to Portfolio Manager!</h2>";
		
		# check the number of portolios
    if (keys(%portfolios) == 0) {
      print "<p>Add a portfolio <a href=\"portfolio.pl?act=add-portfolio\">here</a> to get started.";
    } else {
      print "<p>Below are your portfolios, click to access them and view/modify their contents:</p>";
      while(my ($ID, $name) = each %portfolios){
        print "<li><a href=\"portfolio.pl?act=portfolio-view&portfolioid=$ID\">$name</a></li>";
        print "</br>";
      }
      print "<a style=\"margin-top:15px\" class=\"btn btn-success\" href=\"portfolio.pl?act=add-portfolio\">Add another portfolio</a>";
    }
  }
}

#
# PORTFOLIO VIEW
#

if ($action eq "portfolio-view") {
  my $portfolioID = param("portfolioid");
	my $portfolioname = $portfolios{$portfolioID};
  print "<h2 class=\"page-title\">Manage $portfolioname portfolio:</h2>";
  my @cash = ExecStockSQL("ROW", "select cash from portfolios where PortfolioID = ?", $portfolioID);
  print "You have $cash[0] in this portfolio's cash account </br>";

	
  my @stocks = GetStocks($portfolioID);
#	print "<table>";
#	print "<tr><th>Symbol</th><th>Holdings</th></tr>";
	# deference the 2d array
 # foreach (@stocks) {
#		print "<tr>";
#		my ($symbol, $holdings) = @$_;
 #   print "<td><a href=\"#\">$symbol</a></td>";
#		print "<td>$holdings</td>";
#		print "</tr>";
 # } 
#	print "</table>";
	print "<p>Select your action:<p><p>";
  print "<a href=\"portfolio.pl?act=portfolio-transaction&portfolioid=$portfolioID\">Buy or sell stock.</a><br>";
  print "<a href=\"portfolio.pl?act=portfolio-cashmanage&portfolioid=$portfolioID\">Manage you cash.</a><br>";
  print "<a href=\"portfolio.pl?act=portfolio-transhistory&portfolioid=$portfolioID\">View transfer History</a><br>";
  print "<a href=\"portfolio.pl?act=portfolio-quotedaily&portfolioid=$portfolioID\">Quote today's data</a><br>";
  print "<a href=\"portfolio.pl?act=portfolio-quotebyhistory&portfolioid=$portfolioID\">Quote history's data</a><br>";
  print "<a href=\"portfolio.pl?act=portfolio-presentmarketvalue&portfolioid=$portfolioID\">Present the current value</a><br>";
  print "<a href=\"portfolio.pl?act=portfolio-download&portfolioid=$portfolioID\">Download today's data</a><br>";
  print "<a href=\"portfolio.pl?act=portfolio-checkastock&portfolioid=$portfolioID\">Check a Stock</a><br>";
  print "<a href=\"portfolio.pl?act=portfolio-coeffient&portfolioid=$portfolioID\">Calculate the Coeffient</a><br>";
  print "<a href=\"portfolio.pl?act=portfolio-beta&portfolioid=$portfolioID\">Calculate the Beta</a><br>";
  print "<a href=\"portfolio.pl?act=portfolio-viewstockfuture&portfolioid=$portfolioID\">View the Prediction</a><br>";
  print "<a href=\"portfolio.pl?act=portfolio-usestrategy&portfolioid=$portfolioID\">Use Strategy For Predict</a><br>";
	print"<p><a href=\"portfolio.pl?act=base\">back to main page</a>";
}


if($action eq "portfolio-checkastock"){
	 my $portID = param('portfolioid');
         my @stock = GetMyHoldings($portID);	
	 if(!$run){
 		 print start_form(-name=>'Check a Stock'),
                 h2('Fill the form'),
	         "Choose the stocks you want to look:",radio_group(-name=>'group_choice',-values=>\@stock),
		p,
		"Choose the field you want to see:",radio_group(-name=>'group_field',-values=>['open','high','low','close','volume']),
		p,
		"From(MM/DD/YY):",textfield(-name=>'from'),
		p,
		"To(MM/DD/YY):",textfield(-name=>'to'),
		p,
				 hidden(-name => 'run',-default=>['1']),
			         hidden(-name => 'portfolioid', -default => [$portID]),
				 hidden(-name => 'act',-default=>['portfolio-checkastock']),
				  submit,
				end_form,hr;
		}else{
		my $choice = param('group_choice');
		my $field = param('group_field');
		my $from = param('from');
		my $to = param('to');		        		
		Estimate($choice,$field,$from,$to);
		}

		print "<p><a href=\"portfolio.pl?act=portfolio-view&portfolioid=$portID\">back</a>";
}


if($action eq "portfolio-usestrategy"){
	my $portID  = param('portfolioid');
        my @stock = GetMyHoldings($portID);
	my @cash = ExecStockSQL("ROW","select cash from portfolios where PortfolioID = ?", $portID);
	if(!$run){
		print start_form('UseStrategy'),
		h2('Use the Shannon Ratchet Trading Strategy'),
		"Select a stock:",radio_group(-name=>'group_strategy',-values=>\@stock),
		p,
		"Enter a Trading cost",textfield(-name=>'cost'),
		p,
		"Enter the initial Money for testing:",textfield(-name=>'initial',-default=>'0'),
		p,
		"Enter the days you want to look:(number)",textfield(-name=>'days',-default=>'0'),
		p,
				hidden(-name => 'run',-default=>['1']),
                                 hidden(-name => 'portfolioid', -default => [$portID]),
                                 hidden(-name => 'act',-default=>['portfolio-usestrategy']),
                                  submit,
                                end_form,hr;
		
  		}else{
			my $symbol = param('group_strategy');
			my $tradecost = param('cost');
			my $initialcash = param('initial');
			my $time = param('days'); 
			PredictUseStrategy($symbol, $initialcash,$tradecost,$time)
	}
		print "<p><a href=\"portfolio.pl?act=portfolio-view&portfolioid=$portID\">back</a>";
}


if ( $action eq "portfolio-viewstockfuture" ) {
	my $portID  = param('portfolioid');
	my @stock = GetMyHoldings($portID);
	my $result;
	my $stock;
	if(!$run){
	print start_form('StockView'),
	  h2('View stock future values'),
	   "Select a stock to see its future work:",radio_group(-name=>'group_future',-values=>\@stock),
       	   p,

	  h4('Enter time interval below or choose typical intervals'),
	  "From Now", p, "To:(MM/DD/YY)",  textfield( -name => 'to' ), 
	   p,
#	  popup_menu(
#		-name   => 't',
#		-values => [
#			'',
#			'Tomorrow',
#			'Next week',
#			'Next month',
#			'Next quarter',
#			'Next year',
#			'Next five years'
#		]
#	  ),
#	  p,
			 hidden( -name => 'run', -default => ['1']),
	 		 hidden( -name => 'act', -default => ['viewstockfuture'] ),
			 hidden( -name => 'portfolioid', -default => [$portID]),
				  submit,
				 end_form,hr;
		}else{
			my $from = parsedate("+2 secs");
			my $to = param('to');
			$to = parsedate($to);
			my $symbol = param('group_future');
			PredictStock($symbol,$from,$to);
		}
		print "<p><a href=\"portfolio.pl?act=portfolio-view&portfolioid=$portID\">back</a>";
}

if($action eq "portfolio-beta"){
	my $portID = param('portfolioid');
	my @stock = GetMyHoldings($portID);
	if(!$run){
		print start_form(-name=>'Beta of a Stock'),
                 h2('Fill the form'),
                 "Choose the stocks you want to look:",radio_group(-name=>'group_beta',-values=>\@stock),
                p,
                "From(MM/DD/YY):",textfield(-name=>'from'),
                p,
                "To(MM/DD/YY):",textfield(-name=>'to'),
		p,
				hidden(-name => 'run',-default=>['1']),
                                 hidden(-name => 'portfolioid', -default => [$portID]),
                                 hidden(-name => 'act',-default=>['portfolio-beta']),
                                  submit,
                                end_form,hr;
		}else{
		my $choice = param('group_beta');
                my $from = param('from');
                my $to = param('to');
                BetaCal($choice,$from,$to);
                }
		print "<p><a href=\"portfolio.pl?act=portfolio-view&portfolioid=$portID\">back</a>";
}

if($action eq "portfolio-coeffient"){
         my $portID = param('portfolioid');
         my @stock = GetMyHoldings($portID);    
         if(!$run){
                 print start_form(-name=>'Coeffient'),
                 h2('Fill the form'),
                 "Choose the stocks you want to choose(Please choose two or more stocks):",checkbox_group(-name=>'group_choice',-values=>\@stock),
                p,
                "Choose the first field you want to see:",radio_group(-name=>'group_field1',-values=>['open','high','low','close','volume']),
                p,
		"Choose the second field you want to see:",radio_group(-name=>'group_field2',-values=>['open','high','low','close','volume']),
                p,
                "From(MM/DD/YY):",textfield(-name=>'from'),
                p,
                "To(MM/DD/YY):",textfield(-name=>'to'),
                p,
                                 hidden(-name => 'run',-default=>['1']),
                                 hidden(-name => 'portfolioid', -default => [$portID]),
                                 hidden(-name => 'act',-default=>['portfolio-checkastock']),
                                  submit,
                                end_form,hr;
                }else{
                my @choice = param('group_choice');
                my $field1 = param('group_field1');
		my $field2 = param('group_field2');
                my $from = param('from');
                my $to = param('to');
                CoeCalculate($field1,$field2,$from,$to,@choice);
                }
		 print "<p><a href=\"portfolio.pl?act=portfolio-view&portfolioid=$portID\">back</a>";
}


if($action eq "portfolio-presentmarketvalue"){
	my $portfolioID = param("portfolioid");
#	print "portfolioId $portfolioID";
 	my $portfolioname = $portfolios{$portfolioID};	
 	my @cash = ExecStockSQL("ROW","select cash from portfolios where PortfolioID = ?", $portfolioID);	
#	if($@){
#		print "$@";
#	}
	my $cash;
	print "<h>This is your summary of current portfolio account</h><p>";
	print "The available Cash is: $cash[0]<br>";
	print "<p>";
	my @hold = ExecStockSQL("COL","select SYMBOL from Holdings where PortfolioID=?",$portfolioID);	
	my $cost = $cash[0];
	print "<table border=\"1\">";
	print "<tr><th>StockSymbol</th><th>CurrentPrice</th><th>SharesHolding</th></tr>";
	foreach my $hold (@hold){
		my $price = GetLatest($hold);
		my @amount = ExecStockSQL("ROW","select Shares from Holdings where PortfolioID=? and Symbol=?",$portfolioID,$hold);
		my $amount;
		$cost = $cost + $amount[0] * $price;
	#	print "$cost";
		print "<tr><td><a href=\"portfolio.pl?act=portfolio-nothing&portfolioid=$portfolioID\">$hold</a></td><td>$price</td><td>$amount[0]</td></tr>";
	}
	print "</table>";
	if($@){
		print "error, $@";
	}
	print "<br>And the current worth of your portfolio account would be:<br>";
	print "\$$cost<p>";
#	print "@hold";
#	my ($table)=MakeTable("market-value","2D",["Symbol","Amount","Close"],@hold);
 		
#	print "Show the information:<br>$table";
	 print "<a href = \"portfolio.pl?act=portfolio-view&portfolioid=$portfolioID\">back to $portfolioname</a>";
}


if($action eq "portfolio-transhistory"){
	my $portfolioID = param("portfolioid");
	my $portfolioname = $portfolios{$portfolioID};
	print "<h2 class=\"page-title\">Manage portfolio $portfolioname:</h2>";
	my ($table,$error) = GetTransHistory($portfolioID);
#	my $rom;
#	my @rom = ExecStockSQL("ROW","select * from Transactions");
#	print "$rom[1],$rom[0],$rom[2],$rom[3]";
	if($error){
		print"error happens because $error";
	} else{
		print "Transfer History:<br>$table";
	}
	print "<a href = \"portfolio.pl?act=portfolio-view&portfolioid=$portfolioID\">back to $portfolioname</a>";
}

if($action eq "portfolio-cashmanage"){
  my $portfolioID = param("portfolioid"); 
 	my $portfolioname = $portfolios{$portfolioID}; 

	print "<h2 class=\"page-title\">Manage cash account of $portfolioname :</h2>";

  if($run){
	   my $amount = param('amount');
	   my $action = param('actionforcash');

	   TransferMoney($portfolioID, $action, $amount);
	}

	my @cash = ExecStockSQL("ROW","select cash from portfolios where PortfolioID = ?", $portfolioID);

	print start_form(-name=>'cash management'),
	"You current have cash $cash[0], select your action:",
	p,
	radio_group(-name=>'actionforcash',-values=>['Withdraw','Deposit']),
	p,
	"Choose amount for this action:", textfield(-name=>'amount'),
	p,
	hidden(-name => 'run',-default=>['1']),
	hidden(-name => 'portfolioid', -default => [$portfolioID]),
	hidden(-name=>'act',-default=>['portfolio-cashmanage']),
	submit,
	end_form,
	hr;

	print "<p><a href = \"portfolio.pl?act=portfolio-view&portfolioid=$portfolioID\">back</a>";
}
     
# PORTFOLIO TRANSACTION VIEW (Buy or sell stock)
if ($action eq "portfolio-transaction") {
 	my $portfolioID = param('portfolioid');
	my $portfolioname = $portfolios{$portfolioID};

  if (!$run) {
    print start_form(-name=>'Change Holding'),
    h2('Buy or sell a stock'),
    "Stock Symbol: ", textfield(-name=>'stock_symbol'), p,
    "Shares: ", textfield(-name=>'shares'), p,
    "Type: ", radio_group(-name=>'transtype',-values=>['Buy','Sell'], -default=>['Buy'],-columns=>2,-rows=>1), p,
    hidden(-name => 'run',  -default => ['1']), 
		hidden(-name => 'portfolioid', -default => [$portfolioID]),
    hidden(-name => 'act', -default => ['portfolio-transaction']),
    submit,
    end_form, hr;
  } else {
		my $symbol=param('stock_symbol');
		# uppercase the stock symbol
    $symbol=uc($symbol);

    my $shares = param('shares');
    my $transtype = param('transtype');
    my $logStr;
    if ($transtype eq 'Sell') {
      $logStr = StockSell($portfolioID, $symbol, $shares);
    }

    if ($transtype eq 'Buy') {
     	$logStr = StockBuy($portfolioID, $symbol, $shares);
    }
  }
	print "<p><a href=\"portfolio.pl?act=portfolio-view&portfolioid=$portfolioID\">back to $portfolioname</a>";
}

#
# Sign up
#
# User Add functionaltiy 
#
if ($action eq "sign-up") { 
    if (!$run) { 
      print start_form(-name=>'Sign Up'),
	h2('Sign Up'),
	  "Last Name: ", textfield(-name=>'lastname'),
	    p,
			"First Name: ", textfield(-name=>'firstname'),
			p,
	      "Email: ", textfield(-name=>'email'),
		p,
		  "Password: ", textfield(-name=>'password'),
		    p,
		      hidden(-name=>'run',-default=>['1']),
			hidden(-name=>'act',-default=>['sign-up']),
			  submit,
			    end_form,
			      hr;
    } else {
      my $lastname=param('lastname');
			my $firstname=param('firstname');
      my $email=param('email');
      my $password=param('password');
      my $error;
      $error=UserAdd($lastname, $firstname, $email, $password);
      if ($error) { 
	     print "Can't add user because: $error";
      } else {
	     print $firstname." ".$lastname." was successfully signed up! Now <a href=\"portfolio.pl?act=login\">log in to start managing your portfolio!</a>\n";
      }
    }
}



if($action eq "portfolio-quotebyhistory"){
 	  my $portID = param('portfolioid');

          my @stock = GetMyHoldings($portID);
	# print "$run";
          if(!$run){
	#	print "get here"; 
		print start_form(-name=>'Get History'),
                 h2('Fill the form'),
		"Choose the stocks you want to look:",radio_group(-name=>'group_history',-values=>\@stock),
		p,
		"Or you want to record the market index?",radio_group(-name=>'market',-values=>['Yes','No']),
		p,
		"Choose options:",checkbox_group(-name=>'group_option',-values=>['Open','Low','High','Close','Volume']),
		p,
		"Enter the period of time you want to look at,",
		p,
		"From(MM/DD/YY):",textfield(-name=>'starttime'),
		p,
		"End(MM/DD/YY):",textfield(-name=>'endtime'),
		p,
		"Or select a time period:",scrolling_list(-name=>'group_time',-values=>['use the from and end time','last week to now','last month to now','last quarter to now','last year to now','last five years to now']),
        	p,
		"Display method:",radio_group(-name=>'group_display',-values=>['plot','table']),
		p,
	
					hidden(-name=>'run',-default=>['1']),
					hidden(-name=>'act',-default=>['portfolio-quotebyhistory']),
						submit,
						end_form,hr;
	}else{
		my $choicestock = param('group_history');
		my @option = param('group_option');
		my $starttime = param('starttime');
		my $endtime = param('endtime');
		my $display = param('group_display');
		my $scroll = param('group_time');
		my $marketindex = param('market');
		if($marketindex eq "Yes")
		{ 
			$choicestock = "^IXIC";
		}
		if($scroll eq "last week to now")
		{	$endtime = parsedate("+2 secs");
			$starttime = $endtime - 604800;
		} else{ if($scroll eq "last month to now"){
			$endtime = parsedate("+2 secs");
			$starttime = $endtime - 2592000;
		  	}else{ if($scroll eq "last quarter to now"){
			$endtime = parsedate("+2 secs");
			$starttime = $endtime - 10368000;
				}else { if($scroll eq "last year to now"){
					$endtime = parsedate("+2 secs");
					$starttime = $endtime - 30758400;
					}else { if($scroll eq "last five years to now"){
					$endtime = parsedate("+2 secs");
					$starttime = $endtime - 153792000;
						}else{
							$starttime = parsedate($starttime);
							$endtime = parsedate($endtime);
						}
					}
				}
			}
		}
#		print "stocks you choose are: @choicestock and options are: @option and starttime is : $starttime, 
#		the endtime is : $endtime and the display method is : $display";
		if($display eq "table"){
		 	my ($table,$error)=GetQuoteHistory($choicestock,$starttime,$endtime,$display,@option);
			if($error){
				print "error happens because $error";
			}else{
				print "Table you want:<br>$table";
			}	
		}else{
#			 print header(-type=>'image/png',-expires=>'now',-cookie=>\@outputcookies);
	#		GetQuoteHistory($choicestock,$starttime,$endtime.$display,@option);
		print "<a href=\"portfolio.pl?act=port-new&symbol=$choicestock&from=$starttime&to=$endtime\">print the picture</a>\n";
	#		print header(-type=>'image/png',-expires=>'now',-cookie=>\@outputcookies);
		}
	}
		print "<p><a href=\"portfolio.pl?act=portfolio-view&portfolioid=$portID\">back</a>";
}


if($action eq "port-new"){
	my $symbol = param('symbol');
	my $from = param('from');
	my $to = param('to');

	  my $sql;
       $sql ="select * from (select timestamp,close from cs339.StocksDaily where symbol='$symbol' and Timestamp>$from and Timestamp<$to union select timestamp,close from StocksDailyNew where symbol='$symbol' and Timestamp>$from and Timestamp<$to) order by timestamp";
        print STDERR $sql,"\n";

        my @rows = ExecStockSQL("2D",$sql);

        open(GNUPLOT,"| gnuplot") or die "Cannot run gnuplot";

        print GNUPLOT "set term png\n";           # we want it to produce a PNG
        print GNUPLOT "set output\n";             # output the PNG to stdout
        print GNUPLOT "plot '-' using 1:2 with linespoints\n"; # feed it data to plot
        foreach my $r (@rows) {
                print GNUPLOT $r->[0], "\t", $r->[1], "\n";
         }
        print GNUPLOT "e\n"; # end of data

        close(GNUPLOT);	
}

if($action eq "portfolio-quotedaily"){
	my $portID = param('portfolioid');
	my @stock = GetMyHoldings($portID);
	if(!$run){
	 print start_form(-name=>'Get QuoteDaily'),
	 h2('Fill the form'),
	
	"Choose the stocks you want to choose:",checkbox_group(-name=>'group_stocks',-values=>\@stock),
 	p,
			hidden(-name=>'run', -default=>['1']),
			hidden(-name=>'act', -default=>['portfolio-quotedaily']),
      		       		submit,
				end_form,hr;
	}
	else{
		my @stockselect = param('group_stocks');
		  GetQuoteDaily(@stockselect);
        }
	print "<p><a href=\"portfolio.pl?act=portfolio-view&portfolioid=$portID\">back</a>";
}		


if($action eq "portfolio-download"){
	my $portID = param('portfolioid');
        my @stock = GetMyHoldings($portID);
	my $stock;
        if(!$run){
         print start_form(-name=>'Get Download'),
         h2('Get Download'),
          "DownLoad the whole data",checkbox_group(-name=>'group_stocks',-values=>\@stock),
	p,	
	"Do you want to download your stocks data ",
	p,
	"Or do you want to download all the stocks data in the market?",radio_group(-name=>'all',-values=>['Mine','All']),
	p,
                        hidden(-name=>'run', -default=>['1']),
                        hidden(-name=>'act', -default=>['portfolio-download']),
                                submit,
                                end_form,hr;
        }
        else{
		my @list = param('group_stocks');
		my $list;
		my $stocks;
		my $choice = param('all');
		if($choice eq "All"){
		  $stocks= ExecStockSQL("TEXT",
                   "select symbol from ".GetStockPrefix()."StocksSymbols");
		my @stockslist = split(' ',$stocks);
		my $stockslist;
                  DownloadDaily(@stockslist);
		}
		else{ if($choice eq "Mine"){
			Download(@list);
 		}}
        }
}
		
#		eval { ExecStockSQL("ROW","insert into StocksDailyNew VALUES(?,?,?,?,?,?,?)",$symbol,$timestamp,$open,$high,$low,$close,$volume);};

#		if($@){
#			return "error is: $@";
#		}else{
#			print "insert successfully!";

if ($action eq "add-portfolio") {
  if (!$run) {
    print start_form(-name=>'Add Portfolio'),
    h2('Add Portfolio'),
    "Portfolio Name:", textfield(-name=>'portfolioname'), p,
    "Starting Cash:", textfield(-name=>'cash'), p,
    hidden(-name=>'run', -default=>['1']),
    hidden(-name=>'act', -default=>['add-portfolio']),
    submit,
    end_form, hr;
  } else {
    my $portfolioname = param('portfolioname');
    my $cash = param('cash');
    my $error;
    $error = PortfolioAdd( $portfolioname, $userID, $cash);
    if ($error) {
      print "Couldn't create portfolio because: $error";
    }
    else {
      print "Portfolio $portfolioname was successfully created! Go <a href=\"portfolio.pl\">here</a> to view your new portfolio.";
    }
  }
}

#
# Debugging output is the last thing we show, if it is set
#
#
#print "</center>" if !$debug;

#
# Generate debugging output if anything is enabled.
#
#
if ($debug) {
  print hr, p, hr,p, h2('Debugging Output');
  print h3('Parameters');
  print "<menu>";
  print map { "<li>$_ => ".escapeHTML(param($_)) } param();
  print "</menu>";
  print h3('Cookies');
  print "<menu>";
  print map { "<li>$_ => ".escapeHTML(cookie($_))} cookie();
  print "</menu>";
  my $max= $#sqlinput>$#sqloutput ? $#sqlinput : $#sqloutput;
  print h3('SQL');
  print "<menu>";
  for (my $i=0;$i<=$max;$i++) { 
    print "<li><b>Input:</b> ".escapeHTML($sqlinput[$i]);
    print "<li><b>Output:</b> $sqloutput[$i]";
  }
  print "</menu>";


}

# end container div
#  print "</div>";
if($action eq "port-new"){
}else{
print end_html;
}
#
# The main line is finished at this point. 
# The remainder includes utilty and other functions
#

#
# Generate a table of users
# ($table,$error) = UserTable()
# $error false on success, error string on failure
#
sub UserTable {
  my @rows;
  eval { @rows = ExecStockSQL("Text", "select name, email from Users order by name"); }; 
  if ($@) { 
    return (undef,$@);
  } else {
    return (MakeTable("user_table",
		      "2D",
		     ["Name", "Email"],
		     @rows),$@);
  }
}



sub GetMyHoldings{
	my ($portid) = @_;
	my @stocks;
	eval { @stocks = ExecStockSQL("COL","select Symbol from Holdings where PortfolioID=?",$portid);};
	if($@){
		return (undef,$@);
	}else{
		return (@stocks,$@);
	}
}


sub GetQuoteDaily {
        my @info=("date","time","high","low","close","open","volume");


        my @symbols=@_;

        my $con=Finance::Quote->new();

        $con->timeout(60);

        my %quotes = $con->fetch("usa",@symbols);
        my $symbol;
	my $key;
        
	 foreach $symbol (@_) {
            print $symbol,"\n=========\n";
           if (!defined($quotes{$symbol,"success"})) {
                 print "No Data\n";
          } else {

                foreach $key (@info) {
                         if (defined($quotes{$symbol,$key})) {
                           print $key,"\t",$quotes{$symbol,$key},"\n<p>";
                 }
         }
          }
    print "\n";
        }
}

sub PredictUseStrategy{
	my ($symbol, $initialcash,$tradecost,$time) = @_;


	 my $lastcash=$initialcash;
	 my $laststock=0;
	 my $lasttotal=$lastcash;
	 my $lasttotalaftertradecost=$lasttotal;
	 my $cash=0;
         my $stock=0;
         my $total=0;
         my $totalaftertradecost=0;
         my $day;
         my @data;
         my $stockprice;
         my $data;
         my $currenttotal;
         my $fractioncash;
         my $fractionstock;
         my $thistradecost;
         my $redistcash;
	 my $roi;

         my $roi_annual;
         my $roi_at;
         my $roi_at_annual;
	open(STOCK, "~/www/portfolio/get_data.pl --close $symbol |");



    for($day = 0; $day < $time; $day++){ 

	while (<STOCK>) {
	  chomp;
	   @data=split;
	  $stockprice=$data[1];

	  $currenttotal=$lastcash+$laststock*$stockprice;
	  if ($currenttotal<=0) {
  		  exit;
	  }
	  $fractioncash=$lastcash/$currenttotal;
 	  $fractionstock=($laststock*$stockprice)/$currenttotal;
	  $thistradecost=0;
	  if ($fractioncash >= 0.5 ) {
 		   $redistcash=($fractioncash-0.5)*$currenttotal;
   		 if ($redistcash>0) {
     			 $cash=$lastcash-$redistcash;
      			 $stock=$laststock+$redistcash/$stockprice;
    			 $thistradecost=$tradecost;
   		 } else {
     			 $cash=$lastcash;
     			 $stock=$laststock;
 		   }
 	 }  else {
   		 $redistcash=($fractionstock-0.5)*$currenttotal;
   		 if ($redistcash>0) {
  			    $cash=$lastcash+$redistcash;
   			    $stock=$laststock-$redistcash/$stockprice;
    			    $thistradecost=$tradecost;
    			}
		  }

          $total=$cash+$stock*$stockprice;
	  $totalaftertradecost=($lasttotalaftertradecost-$lasttotal) - $thistradecost + $total;
	  $lastcash=$cash;
	  $laststock=$stock;
	  $lasttotal=$total;
	  $lasttotalaftertradecost=$totalaftertradecost;

	}

#  print STDERR "$day\t$stockprice\t$cash\t".($stock*$stockprice)."\t$stock\t$total\t$totalaftertradecost\n";
 }
#
	  close(STOCK);
	  $roi = 100.0*($lasttotal-$initialcash)/$initialcash;
	  $roi_annual = $roi/($day/365.0);

	  $roi_at = 100.0*($lasttotalaftertradecost-$initialcash)/$initialcash;
	  $roi_at_annual = $roi_at/($day/365.0);


#print "$symbol\t$day\t$roi\t$roi_annual\n";
#

	print "Invested:                        \t$initialcash\n<p>";
	print "Days:                            \t$day\n<p>";
	print "Total:                           \t$lasttotal (ROI=$roi % ROI-annual = $roi_annual %)\n<p>";
	print "Total-after use \$$tradecost/day trade costs: \t$lasttotalaftertradecost (ROI=$roi_at % ROI-annual = $roi_at_annual %)\n<p>";
}
#
#


sub Download{
	my @info = ("date","time","high","low","close","open","volume");

	my @data;
	my @symbols=@_;

	my $con=Finance::Quote->new();

	$con->timeout(60);
	my $date=0;
	my $time=0;
	my $high=0;
	my $low=0;
	my $close=0;
	my $open=0;
	my $volume=0;
	my %quotes = $con->fetch("usa",@symbols);
	my $symbol;
	my $key;
	my $info;
	my $timestamp = 0;
	foreach $symbol (@_) {
 	   print "<p>",$symbol,"\n=========\n";
 	   if (!defined($quotes{$symbol,"success"})) {
       	 print "No Data\n";
  	  } else {
		$date = $quotes{$symbol,$info[0]};
		$time =  $quotes{$symbol,$info[1]};
		$high =  $quotes{$symbol,$info[2]};
		$low =  $quotes{$symbol,$info[3]};
		$close =  $quotes{$symbol,$info[4]};
		$open =  $quotes{$symbol,$info[5]};
		$volume =  $quotes{$symbol,$info[6]};
#		foreach my $key (@info){
 #           if (defined($quotes{$symbol,$key})){
  #              push(@data,$quotes{$symbol,$key});}
   #         else{
    #            push(@data,"----");}
		 $timestamp = parsedate($date,$time);
		eval { ExecStockSQL("ROW","insert into StocksDailyNew VALUES(?,?,?,?,?,?,?)",$symbol,$timestamp,$open,$high,$low,$close,$volume);};
       		if($@)
		{
			print "added before";
	#		print "$@";
		}else{ print "successful";}
	 }
    }
   # return @data;
}
 #       	foreach $key (@info) {
  #         		 if (defined($quotes{$symbol,$key})) {
   #           		  print $key,"\t",$quotes{$symbol,$key},"\n";
    #        }
     #   }
   # }
  #  print "\n";
#	}
	








sub DownloadDaily{
 	my @symbols = @_;
        my @info=("date","time","high","low","close","open","volume");
        my $con=Finance::Quote->new();

        $con->timeout(60);

        my %quotes = $con->fetch("usa",@symbols);
        my $symbol;
        my $key;
	my $info;
	my $sum=0;
         foreach $symbol (@_) {
        #   if (!defined($quotes{$symbol,"success"})) {
         #        print "No Data\n";
         # } else {
	#	print "$symbol";
		 my $date=0;
		 my $time=0;
		 my $high=0;
		 my $low=0;
		 my $close=0;
		 my $open=0;
		 my $volume=0;
		 my $timestamp=0;
		 if (defined($quotes{$symbol,$info[0]})){
		  	$date = $quotes{$symbol,$info[0]};
		}else{
		  	$date = 0;}
		 if (defined($quotes{$symbol,$info[1]})){
		  	 $time = $quotes{$symbol,$info[1]};
		}else{
		  	 $time = 0;}
		 if (defined($quotes{$symbol,$info[2]})){
		  	$high = $quotes{$symbol,$info[2]};
		}else{
		  	$high= 0;}
		 if (defined($quotes{$symbol,$info[3]})){
		  	 $low = $quotes{$symbol,$info[3]};
		}else{
		  	 $low = 0;}
		 if (defined($quotes{$symbol,$info[4]})){
		  	 $close = $quotes{$symbol,$info[4]};
		}else{
		  	 $close = 0;}
		 if (defined($quotes{$symbol,$info[5]})){
		  	 $open = $quotes{$symbol,$info[5]};
		}else{
		  	 $open = 0;}
		 if (defined($quotes{$symbol,$key})){
		  	 $volume = $quotes{$symbol,$info[6]};
		}else{
		  	 $volume = 0;}
		if($date != 0){
			if($time !=0){
			   $timestamp = parsedate($date,$time);}
			else{
			   $timestamp = parsedate($date);}}
		else{
			 $timestamp = 0;}
	#	}else{
	#		my $timestamp = "----";}
#		my $q = "insert into StocksDailyNew VALUES($symbol,$timestamp,$open,$high,$low,$close,$volume)";
#		ExecStockSQL("ROW",$q);
		 eval { ExecStockSQL("ROW","insert into StocksDailyNew VALUES(?,?,?,?,?,?,?)",$symbol,$timestamp,$open,$high,$low,$close,$volume);};
		if($@){
#			print "error is $@";
		}else{
#			$sum +=1;
			print "add data successfully";}
         #       foreach $key (@info) {
          #               if (defined($quotes{$symbol,$key})) {
           #                print $key,"\t",$quotes{$symbol,$key},"\n";
            #     }
        # }
        	
         # }
    print "\n";
        }
}



sub GetQuoteHistory {
	my($symbol,$from,$to,$display,@options)=@_;	

	my $fromtemp = ParseDateString("epoch $from");
	my $totemp = ParseDateString("epoch $to");
	
	my %query = (
          symbols    => [$symbol],
          start_date => $fromtemp,
          end_date   => $totemp,
         );
	my $output;

	my $q = new Finance::QuoteHist::Yahoo(%query) or die "Cannot issue query\n";

#	if ($display eq "plot") {
 #		 open(DATA,">_plot.in") or die "Cannot open plot file\n";
#		  $output = DATA;
#		} else {
 #		 $output = STDOUT;
#		}
	my $row;
     if($symbol eq "^IXIC"){
		foreach $row ($q->quotes()) {
                 my @out;
                 my $qsymbol;
                 my $qdate;
                 my $qopen;
                 my $qhigh;
                 my $qlow;
                 my $qclose;
                 my $qvolume;

                  ($qsymbol, $qdate, $qopen, $qhigh, $qlow, $qclose, $qvolume) = @{$row};
                 my $timestamp = parsedate($qdate);
                  eval { ExecStockSQL("ROW","insert into StocksDailyNew(SYMBOL,TIMESTAMP,OPEN,HIGH,LOW,CLOSE,VOLUME) VALUES(?,?,?,?,?,?,?)",$qsymbol,$timestamp,$qopen,$qhigh,$qlow,$qclose,$qvolume);};
		}
		print "Add Market Index Data Succeffully";
	}else{

	if($to <= 1157346000)
	{
		my $optiontemp = join(",",@options);
		my @table;
		if($display eq "table"){
			my $ql= "select $optiontemp from cs339.StocksDaily where SYMBOL=\'$symbol\' and TIMESTAMP>$from and TIMESTAMP<$to";
			@table = ExecStockSQL("2D",$ql);
			if($@){
				print "error is $@";
			}else{
                		return(MakeTable("StockHistory","2D",[@options],@table),$@);
               		 }
		}
	}else{
			
	foreach $row ($q->quotes()) {
 		 my @out;
		 my $qsymbol;
		 my $qdate;
		 my $qopen;
		 my $qhigh;
		 my $qlow;
		 my $qclose;
		 my $qvolume;

		  ($qsymbol, $qdate, $qopen, $qhigh, $qlow, $qclose, $qvolume) = @{$row};
		 my $timestamp = parsedate($qdate);

		  eval { ExecStockSQL("ROW","insert into StocksDailyNew(SYMBOL,TIMESTAMP,OPEN,HIGH,LOW,CLOSE,VOLUME) VALUES(?,?,?,?,?,?,?)",$qsymbol,$timestamp,$qopen,$qhigh,$qlow,$qclose,$qvolume);};

	}
	my $optiontemp = join(",",@options);
	my $tabletemp = join(",",map{"\"".$_."\""}@options);
	my $ql;
	if($display eq "table"){
 	 my @table;	
	 my $table;
	  	  if($from > 1157346000){
			 $ql= "select $optiontemp from StocksDailyNew where SYMBOL=\'$symbol\' and TIMESTAMP>$from and TIMESTAMP<$to";
		}else{
			 $ql= "select $optiontemp from StocksDailyNew where SYMBOL=\'$symbol\' and TIMESTAMP>$from and TIMESTAMP<$to union select $optiontemp from cs339.StocksDaily where SYMBOL=\'$symbol\' and TIMESTAMP>$from and TIMESTAMP<$to";
		}
	 @table = ExecStockSQL("2D",$ql);
	if($@)
	{
#		print "$@";
		return(undef,$@);
	}
	else{
		my $try = "[$tabletemp]";
		print "$try";
		return(MakeTable("StockHistory","2D",[@options],@table),$@);
		}
	}else{
#	print "get in here";
	my $sql;
	$sql ="select * from (select timestamp,close from cs339.StocksDaily where symbol='$symbol' and Timestamp>$from and Timestamp<$to union select timestamp,close from StocksDailyNew where symbol='$symbol' and Timestamp>$from and Timestamp<$to) order by timestamp";
	my @rows = ExecStockSQL("2D",$sql);
	open(GNUPLOT,"| gnuplot") or die "Cannot run gnuplot";

	print GNUPLOT "set term png\n";           # we want it to produce a PNG
	print GNUPLOT "set output\n";             # output the PNG to stdout
	print GNUPLOT "plot '-' using 1:2 with linespoints\n"; # feed it data to plot
	foreach my $r (@rows) {
    		print GNUPLOT $r->[0], "\t", $r->[1], "\n";
 	 }
 	print GNUPLOT "e\n"; # end of data

        close(GNUPLOT);
	
	}
	}
   }
}
	

sub Estimate{
	my ($symbol,$field,$from,$to)=@_;
	my $sql;
	$from = parsedate($from);
	$to = parsedate($to);
	if($to <= 1157346000){
	 $sql = "select count($field), avg($field), stddev($field), min($field), max($field)  from ".GetStockPrefix()."StocksDaily where symbol='$symbol'";
 	 $sql.= " and timestamp>=$from" if $from;
 	 $sql.= " and timestamp<=$to" if $to;
	}else{
         $sql = "select count($field), avg($field), stddev($field), min($field), max($field)  from ".GetStockPrefix()."StocksDaily union select count($field), avg($field), stddev($field), min($field), max($field)  from StocksDailyNew where symbol='$symbol'";
         $sql.= " and timestamp>=$from" if $from;
         $sql.= " and timestamp<=$to" if $to;
        }
	my $n;
	my $mean;
	my $std;
	my $min;
	my $max;
	  ($n,$mean,$std,$min,$max) = ExecStockSQL("ROW",$sql);
	
	print "You choose Stock $symbol and its Field $field:<p>";
	print "<p>The N value is $n<p>The Mean value is $mean<p> The Std value is $std<p>The Min value is $min<p>The Max value is $max";
#	  print join("\t",$symbol,$field, $n, $mean, $std, $min, $max, $std/$mean),"\n";
}


sub BetaCal{
	my($symbol,$from,$to)=@_;
	$from = parsedate($from);
	$to = parsedate($to);
	my $field1 = "close";
	my $field2 = "close";
	my %covar;
	my $markindex="^IXIC";
	print "<table border=\"1\"><tr><th>Coeff Var</th><th>Beta</th></tr>";
	my $cover;
	my $sql;
	my $count;
	my $mean_f1;
	my $mean_f2;
	my $std_f2;
	my $std_f1;
	my $beta;
	my $square;	
	my $var;
	$sql = "select count(*),avg(l.$field1),stddev(l.$field1),avg(r.$field2),stddev(r.$field2) from StocksView l join StocksView r on l.timestamp= r.timestamp where l.symbol='$symbol' and r.symbol='$markindex'";
	 $sql.= " and l.timestamp>=$from" if $from;
         $sql.= " and l.timestamp<=$to" if $to;
	 ($count, $mean_f1,$std_f1, $mean_f2, $std_f2) = ExecStockSQL("ROW",$sql);	
	 $var = $std_f1 / $mean_f1;
	 print "<tr><td>$var</td>";
	 if ($count<30) {
                   $covar{$symbol}{$markindex}='NODAT';
            #       $corrcoeff{$symbol}{$markindex}='NODAT';
                  } else {
                         $sql = "select avg((l.$field1 - $mean_f1)*(r.$field2 - $mean_f2)) from StocksView l join StocksView r on  l.timestamp=r.timestamp where l.symbol='$symbol' and r.symbol='$markindex'";
			 $sql.= " and l.timestamp>= $from" if $from;
                         $sql.= " and l.timestamp<= $to" if $to;
                        print STDERR $sql,"\n";
                         ($covar{$symbol}{$markindex}) = ExecStockSQL("ROW",$sql);
			$square = $std_f2 * $std_f2;
			$beta = $covar{$symbol}{$markindex} / $square;
				
			print "<td>$beta</td></tr>";
		}
		print "</table>";
}

sub CoeCalculate{
	my($field1,$field2,$from,$to,@symbols)=@_;
	my $symbols;
	$from = parsedate($from);
	$to = parsedate($to);
	my ($i,$j,$s1,$s2,$sql,$count,$mean_f1,$mean_f2,$std_f1,$std_f2)=@_;
	my %covar;
	my %corrcoeff;
	my ($covar,$corrcoeff);
	print "<table border=\"1\"><tr><th>Symbols Group</th><th>Covar</th><th>Corrcoeff</th></tr>";
	for ($i=0;$i<=$#symbols;$i++) {
 		 $s1=$symbols[$i];
		 print "$symbols[$i]";
	  for ($j=$i; $j<=$#symbols; $j++) {
		 $s2=$symbols[$j];
		 $sql = "select count(*),avg(l.$field1),stddev(l.$field1),avg(r.$field2),stddev(r.$field2) from StocksView l join StocksView r on l.timestamp= r.timestamp where l.symbol='$s1' and r.symbol='$s2'";
   		 $sql.= " and l.timestamp>=$from" if $from;
  		 $sql.= " and l.timestamp<=$to" if $to;
		print STDERR $sql,"\n";
		print "$s1 x $s2"; 
  		 ($count, $mean_f1,$std_f1, $mean_f2, $std_f2) = ExecStockSQL("ROW",$sql);

		 if ($count<30) { 
   		   $covar{$s1}{$s2}='NODAT';
    		   $corrcoeff{$s1}{$s2}='NODAT';
		  } else {
			 $sql = "select avg((l.$field1 - $mean_f1)*(r.$field2 - $mean_f2)) from StocksView l join StocksView r on  l.timestamp=r.timestamp where l.symbol='$s1' and r.symbol='$s2'";
     			 $sql.= " and l.timestamp>= $from" if $from;
  			 $sql.= " and l.timestamp<= $to" if $to;
			print STDERR $sql,"\n";
			print "<tr><td>$s1 x $s2</td>";
      			 ($covar{$s1}{$s2}) = ExecStockSQL("ROW",$sql);
			print "<td>$covar{$s1}{$s2}</td>";

     			 $corrcoeff{$s1}{$s2} = $covar{$s1}{$s2}/($std_f1*$std_f2);
			print "<td>$corrcoeff{$s1}{$s2}</td></tr>";
   			 }
 		 }
	} 
		print "</table>";
}



sub PredictStock {
	my ( $symbol, $from, $to ) = @_;
	my $outfile;
	my $days_ahead = int( ( $to - $from ) / 86400.0 );
	print "<p>Total days: ", $days_ahead;
	system
	  "~/www/portfolio/get_data.pl --close --from=$from --to=$to $symbol > _plot.in";
	system
	  "~/www/portfolio/time_series_project _plot.in $days_ahead AR 16 1>predictor.out";
	system "tail -n $days_ahead predictor.out > predictor.plot";

	my $num_days   = ( $to - $from ) / 86400.0;

	my @xlabel;

		@xlabel = PlotwithDay( $from, $to );

	my $xtics = "(" . join( ", ", @xlabel ) . ")";
	$from = localtime($from);
	$to   = localtime($to);
	print "<p>From: $from\n";
	print "To: $to\n";
	$outfile =
	  GnuPlotFuture( "$symbol", "predictor.plot", "image.png", "$from", "$to",
		"$xtics" );
	print "<img src=\"" . $outfile . "\">";
}

sub GnuPlotFuture
 {
   my ($symbol, $datafile, $outputfile,$from,$to,$xtics)=@_;
   my $format = "%Y";		 
   open(GNUPLOT,"|gnuplot");
   print GNUPLOT "set terminal png\n";
   print GNUPLOT "set output \"$outputfile\"\n";
   print GNUPLOT "set xtics $xtics \n";
   print GNUPLOT "set size 2.0, 1.0\n";
   print GNUPLOT "set style fill empty\n";
   print GNUPLOT "set title '$symbol'\nset xlabel 'Time' 0.0,-1.0\nset ylabel 'Price'\n";
   print GNUPLOT "plot \"$datafile\" using 3 with linespoints\n";
   close(GNUPLOT);
   return $outputfile;
}

sub PlotwithDay {
    my ($from, $to) = @_;
    my @xlabel;
    
    my @mons = qw(NOF Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec);
    my ($fromday, $frommonth, $fromyear) = (localtime($from))[3,4,5];
    $fromyear += 1900;
    my $from_timestamp = timelocal(0,0,0,$fromday,$frommonth,$fromyear);

    my ($today, $tomonth,$toyear) = (localtime($to))[3,4,5];
    $toyear += 1900;
    my $to_timestamp = timelocal(0,0,0,$today,$tomonth,$toyear);
    my ($previous_month, $previous_year) = (0,0);
    do {
        my ($day, $month,$year) = (localtime($from_timestamp))[3,4,5];
        $month += 1;
        $year += 1900;
        my $xtic = "$day";
        if ($month != $previous_month) {
            $xtic .= "\\n$mons[$month] $year";
        }
        push @xlabel, "\"$xtic\" " . $from_timestamp;
        ($previous_month, $previous_year) = ($month, $year);
        $from_timestamp += 86400;
    } while ($from_timestamp <= $to_timestamp);
  
}
#
# Add a portfolio
# call with portfolio_name, cash
#
# returns false on success, error string on failure
#
# PortfolioAdd($portfolio_name, $cash, $email)
sub PortfolioAdd {
  eval {
    ExecStockSQL("ROW", "insert into portfolios (PortfolioName, UserId, cash) values (?,?,?)", @_);
  };
  return $@;
}

sub GetPortfolios {
	my ($userID) = @_;
  my @rows;
  eval {
    @rows = ExecStockSQL("2D", "select PortfolioName, PortfolioID from portfolios where UserID= ? ", $userID);
  };
	my %idtoname;
	foreach(@rows) {
		my ($name, $ID) = @$_;
		$idtoname{$ID} = $name;
	}
  return %idtoname;
}

sub TransferMoney{
	my ($portfolioID, $action, $amount) = @_;

	my @currentcash;
	my $currentcash;
	eval { @currentcash = ExecStockSQL("ROW","select Cash from Portfolios where PortfolioID=?",$portfolioID);};
  print "You used to have cash $currentcash[0] in this portfolio.<br>";
	if(uc($action) eq 'WITHDRAW') {
		if($currentcash[0] < $amount) {
			print "Not enough for a withdraw of $amount !<br><br>";
			return;
		} else {
			$currentcash[0] -= $amount;
		}
	} 

	if(uc($action) eq 'DEPOSIT') {
		$currentcash[0] += $amount;
	}
	
	print "<br>";

	eval { ExecStockSQL("COL","update Portfolios set Cash=? where PortfolioID=?",$currentcash[0],$portfolioID);};
	return $@;
}

sub StockBuy {
  my ($portfolioID,$symbol,$shares)=@_;
	print $portfolioID."<br>";
  my $price = GetLatest($symbol);
  my $action = 'buy';
  DotheTrans($portfolioID,$symbol,$shares,$price,$action);
}

sub StockSell {
  my ($portfolioID,$symbol,$shares)=@_;
  my  $price = GetLatest($symbol);
  my $action = 'sell';
  DotheTrans($portfolioID,$symbol,$shares,$price,$action);
}

sub DotheTrans{
	my($portfolioID, $symbol, $shares, $price, $action)=@_;

	my @currentcash;
	my @currentshares;
	my $time= parsedate("+2 secs");
	
	eval {@currentcash = ExecStockSQL("COL","select Cash from Portfolios where PortfolioID=?",$portfolioID);};
	if($@) {
		print $@;
		return;
	}
	
	eval {@currentshares = ExecStockSQL("ROW","select Shares from Holdings where PortfolioID=? and Symbol=?",$portfolioID,$symbol);};
	if($@) {
		print $@;
		return;
	}

	my $cost = $price * $shares;

	print "current stock is $price and the amount is $shares";
	print "<br>";
	
	my $newshares;
	# if there exists current shares for this stock
	if(@currentshares > 0) {
		$newshares = $currentshares[0];
	} else {
		print "No shares of this stock in portfolio!";
	}

	if($action eq 'buy') {
		if($currentcash[0]< $cost) {
			print "You cannot do this because you don't have enough money";
		} else {
			$newshares += $shares;
			if($newshares == $shares){	
				eval { ExecStockSQL("ROW","insert into Holdings(PortfolioID,Symbol, Shares) values(?,?,?)",$portfolioID,$symbol,$shares);};
				if($@) {
					print $@;
					return;
				}
			} else {
				eval { ExecStockSQL("ROW","update Holdings set Shares=? where PortfolioID=? and Symbol=?", $newshares, $portfolioID, $symbol);};
			}

			# update cash after transaction has finished
			$currentcash[0] -= $cost;
			print "cost is $cost and the currentcash left would be $currentcash[0]";
			eval { ExecStockSQL("ROW","update Portfolios set Cash=? where PortfolioID=?",$currentcash[0],$portfolioID);};
			if($@) {
				print $@;
				return;
			}

			eval { ExecStockSQL("COL","insert into Transactions values(?, ?, ?, 'Buy', ?, ?)",$portfolioID,$time,$symbol,$shares, $price);};	
		}
	}

	if($action eq 'sell'){
		if($newshares < $shares){
			print " error, there isn's so much stocks for you to sell";
		} else {
			$newshares -= $shares;
			$currentcash[0] += $cost;
			print "current shares would be $newshares ad the quantity would be $shares";
			eval{ ExecStockSQL("COL","update Portfolios set Cash=? where PortfolioID=?",$currentcash[0],$portfolioID);};

			eval{ ExecStockSQL("COL","update Holdings set Shares =? where portfolioID=? and Symbol=?",$newshares, $portfolioID, $symbol);};

			eval{ ExecStockSQL("COL","insert into Transactions values(?,?,?,'Sell',?, ?)",$portfolioID,$time,$symbol,$shares, $price);};
		}
	}
}


sub GetStocks {
  my @rows;
	my $portfolioID = @_;
  eval {
    @rows = ExecStockSQL("2D", "select symbol, shares from holdings where portfolioID = ?", $portfolioID);
  };
  return @rows;
}

# Get the latest stock price
sub GetLatest{
  my ($symbol) = @_;
  $symbol =uc($symbol);
	my @symbols;
	push @symbols, $symbol;
	
	my $quoter = Finance::Quote->new();
	$quoter->timeout(100);
	my %stocks = $quoter->fetch("usa", @symbols);
	
	foreach my $stock (@symbols) {
		unless ($stocks{$stock, "success"}) {
			print "Failed to look up ".$stock." - ".$stocks{$stock, "errormsg"}."\n".
			next;
		}

		return $stocks{$stock, "price"};
	}
}


#use in view transfer history page
sub GetTransHistory {
	my($portfolioID)=@_;
	my @record;
	eval { @record = ExecStockSQL("2D","select TimeStamp, Symbol, TransactionType, Shares,Price from Transactions where PortfolioID=?",$portfolioID);};
	if($@){
		return (undef,$@);
		}
	
	return (MakeTable("record-table","2D",
			  ["TimeStamp","Symbol","TransactionType","Shares","Price"],
			  @record),$@);
}
#
# Add a user
# call with name,password,email
#
# returns false on success, error string on failure.
# 
# UserAdd($name,$password,$email)
#
sub UserAdd { 
  eval { ExecStockSQL("ROW", "insert into Users (LastName, FirstName , email, password) values (?,?,?,?)", @_);};
  return $@;
}

#
# Delete a user
# returns false on success, $error string on failure
# 
sub UserDel { 
  eval {ExecStockSQL("delete from Users where UserID = ?", @_);};
  return $@;
}

sub HoldingCount{
  my ($portfolioID, $symbol)=@_;
  my @col;
  my $countOf;
  eval {@col=ExecStockSQL("select Amount from holdings where portfolio=? and symbol=rpad(upper(?),16)", $portfolioID, $symbol);};
  if ($@) { 
    return 0;
    print $@;
  } else {
   return $col[0];}
}

#
#
# Check to see if user and password combination exist
#
# It returns the userID which is then cached for following operations
#
#
sub ValidUser {
  my ($email,$password)=@_;
  my @row = ExecStockSQL("ROW", "select userID from Users where email=? and password=?",$email,$password);
	# @row contains the userID or NULL
	return @row;
}

#
# Given a list of scalars, or a list of references to lists, generates
# an html table
#
#
# $type = undef || 2D => @list is list of references to row lists
# $type = ROW   => @list is a row
# $type = COL   => @list is a column
#
# $headerlistref points to a list of header columns
#
#
# $html = MakeTable($id, $type, $headerlistref,@list);
#
sub MakeTable {
  my ($id, $type, $headerlistref, @list)=@_;
  my $out;
  #
  # Check to see if there is anything to output
  #
  if ((defined $headerlistref) || ($#list>=0)) {
    # if there is, begin a table
    #
    $out="<table id=\"$id\" border>";
    #
    # if there is a header list, then output it in bold
    #
    if (defined $headerlistref) { 
      $out.="<tr>".join("",(map {"<td><b>$_</b></td>"} @{$headerlistref}))."</tr>";
    }
    #
    # If it's a single row, just output it in an obvious way
    #
    if ($type eq "ROW") { 
      #
      # map {code} @list means "apply this code to every member of the list
      # and return the modified list.  $_ is the current list member
      #
      $out.="<tr>".(map {defined($_) ? "<td>$_</td>" : "<td>(null)</td>" } @list)."</tr>";
    } elsif ($type eq "COL") { 
      #
      # ditto for a single column
      #
      $out.=join("",map {defined($_) ? "<tr><td>$_</td></tr>" : "<tr><td>(null)</td></tr>"} @list);
    } else { 
      #
      # For a 2D table, it's a bit more complicated...
      #
      $out.= join("",map {"<tr>$_</tr>"} (map {join("",map {defined($_) ? "<td>$_</td>" : "<td>(null)</td>"} @{$_})} @list));
    }
    $out.="</table>";
  } else {
    # if no header row or list, then just say none.
    $out.="(none)";
  }
  return $out;
}


#
# Given a list of scalars, or a list of references to lists, generates
# an HTML <pre> section, one line per row, columns are tab-deliminted
#
#
# $type = undef || 2D => @list is list of references to row lists
# $type = ROW   => @list is a row
# $type = COL   => @list is a column
#
#
# $html = MakeRaw($id, $type, @list);
#
sub MakeRaw {
  my ($id, $type,@list)=@_;
  my $out;
  #
  # Check to see if there is anything to output
  #
  $out="<pre id=\"$id\">\n";
  #
  # If it's a single row, just output it in an obvious way
  #
  if ($type eq "ROW") { 
    #
    # map {code} @list means "apply this code to every member of the list
    # and return the modified list.  $_ is the current list member
    #
    $out.=join("\t",map { defined($_) ? $_ : "(null)" } @list);
    $out.="\n";
  } elsif ($type eq "COL") { 
    #
    # ditto for a single column
    #
    $out.=join("\n",map { defined($_) ? $_ : "(null)" } @list);
    $out.="\n";
  } else {
    #
    # For a 2D table
    #
    foreach my $r (@list) { 
      $out.= join("\t", map { defined($_) ? $_ : "(null)" } @{$r});
      $out.="\n";
    }
  }
  $out.="</pre>\n";
  return $out;
}

