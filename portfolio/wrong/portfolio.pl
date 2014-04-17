#!/usr/bin/perl -w


#
# Debugging
#
# database input and output is paired into the two arrays noted
#
my $debug=0; # default - will be overriden by a form parameter or cookie
my @sqlinput=();
my @sqloutput=();
my $dbuser="nwu583";
my $dbpasswd="zdbGr2Oy3";
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
use Date::Manip;
use Time::CTime;
use stock_data_access;


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
my $user = undef;
my $email = undef;
my $passwd = undef;
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

my $dstr;

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
  ($email,$passwd,$user) = split(/\//,$inputcookiecontent);
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
    ($email,$passwd) = (param('email'),param('passwd'));
    if (ValidUser($email,$passwd)) { 
      # if the user's info is OK, then give him a cookie
      # that contains his email and password 
      # the cookie will expire in one hour, forcing him to log in again
      # after one hour of inactivity.
      # Also, land him in the base query screen
      $outputcookiecontent=join("/",$email,$passwd,$user);
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
    ($user,$passwd,$email)=(undef,undef,undef);
  }
} 


#
# If we are being asked to log out, then if 
# we have a cookie, we should delete it.
#
if ($action eq "logout") {
  $deletecookie=1;
  $action = "base";
  $user = undef;
  $passwd = undef;
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
print "<html style=\"height: 100\%\">";
print "<head>";
print "<title>Portfolio Management</title>";

# Include JQuery
print "<script type=\"text/javascript\" src=\"js/jquery-1.10.2.min.js\"></script>";

# import Twitter Bootstrap to pretty-ify things
print "<link media=\"screen\" rel=\"stylesheet\" href=\"./bootstrap/css/bootstrap.min.css\">";
print "<script type=\"text/javascript\" src=\"./bootstrap/js/bootstrap.min.js\"></script>";

print "</head>";

print "<body style=\"height:100\%;margin:0\">";

  
my @portfolios = GetPortfolios();

# THE HEADER
print "<div class=\"navbar navbar-fixed-top\">";
  print "<div class=\"navbar-inner\">";
    print "<div class=\"container\">";
      print "<ul class=\"nav\">";
        print "<li><a href=\"portfolio.pl\" style=\"font-weight:bold; margin-left:-100px\">Portfolio Manager</a></li>";
        if ($email) {
          print "<li style=\"margin-top:10px\">You are logged in as $user</li>";
        }
      print "</ul>";
      print "<ul class=\"nav pull-right\">";
        if (!$email) {
          print "<li><a href=\"portfolio.pl?act=login\">Sign In</a></li>";
        }
        else {
          print "<li class=\"dropdown\">";
            print "<a class=\"dropdown-toggle\" data-toggle=\"dropdown\" href=\"#\">Portfolios<b class=\"caret\"></b></a>";
              print "<ul class=\"dropdown-menu\" role=\"menu\" aria-labelledby=\"dLabel\">";
                if (($#portfolios + 1) >= 1) {
                  foreach (@portfolios) {
                    print "<li><a href=\"portfolio.pl?act=portfolio-view&portfolio=$_\">$_</a></li>";
                  }
                }
                print "<li class=\"divider\"></li>";
                print "<li><a class=\"btn btn-success\" href=\"portfolio.pl?act=add-portfolio\">Add</a></li>";
              print "</ul>";
            print "</a>";
          print "</li>";
          print "<li><a href=\"portfolio.pl?act=logout&run=1\">Sign Out</a></li>";
        }
      print "</ul>";
    print "</div>";
  print "</div>";
print "</div>";

#
#
# Wrapping all future HTML in a div to offset it for the header
#
#

print "<div style=\"margin-top:50px; margin-left:8%; width:75%;\" class=\"hero-unit\">";

#
#
# The remainder here is essentially a giant switch statement based
# on $action. 
#
#
#


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

  #print img{src=>'plot_stock.pl?type=plot', height=>50, width=>60};
  
  #
  # User mods
  #
  #
  if (!$email) {
    print "<h2 class=\"page-title\">You are not signed in, but you can <a href=\"portfolio.pl?act=login\">login</a></h2>";
  } 
  else {
	my $userid = param("userID");
    print "<h2 class=\"page-title\">Welcome to Portfolio Manager!</h2>";
    if (($#portfolios + 1) < 1) {
      print "<p>Add a portfolio <a href=\"portfolio.pl?act=add-portfolio&userid=$userid\">here</a> to get started.";
    }
    else {
      print "<p>Below are your portfolios, click to access them and view/modify their contents:</p>";
      foreach (@portfolios) {
        print "<li><a href=\"portfolio.pl?act=portfolio-view&userid=$userid&portfolio=$_\">$_</a></li>";
        print "</br>";
      }
      print "<a style=\"margin-top:15px\" class=\"btn btn-success\" href=\"portfolio.pl?act=add-portfolio&userid=$userid\">Add another portfolio</a>";
    }
  }

}

#
# PORTFOLIO VIEW
#

if ($action eq "portfolio-view") {
  my $portfolioID = param("portfolioID");
  my $userid = param("userid");
  print "<h2 class=\"page-title\">Manage $portfolioID portfolio:</h2>";
  my @cash = ExecStockSQL("ROW", "select cash from portfolios where PortfolioID = ?", $portfolioID);
  print "You have \$$cash[$0] in this portfolio's cash account </br>";
  my @stocks = GetStocks($portfolioID);
  foreach (@stocks) {
    print "<li><a href=\"#\">$_</a></li>";
    print "</br>";
  } 
  print "<a href=\"portfolio.pl?act=portfolio-transaction&userid=$userid&portfolio=$portfolioID\">Buy or sell stock.</a><br>";
  print "<a href=\"portfolio.pl?act=portfolio-cashmanage&userid=$userid&portfolio=$portfolioID\">Manage you cash.</a><br>";
  print "<a href=\"portfolio.pl?act=portfolio-transhistory&userid=$userid&portfolio=$portfolioID\">View transfer History</a><br>";
}


if($action eq "portfolio-transhistory"){
	my $portfolioID = 53;
	print "<h2 class=\"page-title\">Manage $portfolioID portfolio:</h2>";
	my ($table,$error) = GetTransHistory($portfolioID);
#	my $rom;
#	my @rom = ExecStockSQL("ROW","select * from Transactions");
#	print "$rom[1],$rom[0],$rom[2],$rom[3]";
	if($error){
		print"error happens because $error";
		}
	else{

		print "Transfer History:<br>$table";
	}
}


if($action eq "portfolio-cashmanage"){
   my $portfolioID = 53; 
   my $userid = param("userid");
    if(!$run){  
#	my $portfolioID = 3;
	print "<h2 class=\"page-title\">Manage $portfolioID portfolio:</h2>";
#	print start_form(-name=>'cash management'),
	my @cash = ExecStockSQL("ROW","select cash from portfolios where PortfolioID = ?", $portfolioID);
	print start_form(-name=>'cash management'),
	 "You current have cash \$$cash[$0], select your action:",
	p,
		radio_group(-name=>'actionforcash',-values=>['Withdraw','DEPOSIT']),
		p,
		"Choose amount for this action:", textfield(-name=>'amount'),
		p,
#	print "<a href=\"portfolio.pl?act=portfolio-withdraw&portfolio=$portfolioID\">Withdraw</a><br>";
#	print "<a href=\"portfolio.pl?act=portfolio-deposit&portfolio=$portfolioID\">Deposit</a><br>";
			hidden(-name=>'run',-default=>['1']),
			hidden(-name=>'portfolio_name',-default=>[$portfolioID]),
			hidden(-name=>'act',-default=>['portfolio-cashmanage']),
				submit,
				end_form,
				hr;
	}
	else{
	   my $amount = param('amount');
	   my $action = param('actionforcash');
	   my $portID = $portfolioID;
	   my @datatime = localtime(time);
	   my $datatime;
	   my $user;
	  # my $timeold = parsedate("12/11/2010");
	  # print "old time is $timeold";
	   my $timenow = parsedate("+2 secs");
	  # print "current time is $timenow";
	 #  print "old time is $timeold ";
	 #  my $thetime = ctime($timeold);
	    my $portname = GetPortName($portID);
	    $user = GetPortUser($portID);
	  # print "amount is: $amount and action is: $action and portID is: $portID and time is: @datatime seconds are: $datatime[0] and minutes are: $datatime[1] and hour is $datatime[2] and days past is $datatime[3] month is ($datatime[4]+1)" ;
	   TransferMoney($portID,$portname,$action,$user,$amount);
	}
}
     
	

#
# PORTFOLIO TRANSACTION VIEW (Buy or sell stock)
if ($action eq "portfolio-transaction") {
 	my $portfolioID = 53;
   if (!$run) {
    my $portfolio=param('portfolio');
#    my $portfolioID = 53;
    print start_form(-name=>'Change Holding'),
    h2('Buy or sell a stock'),
    "Stock Symbol:", textfield(-name=>'stock_symbol'), p,
    "Quantity:", textfield(-name=>'quantity'), p,
    "Direction: ", radio_group(-name=>'direction',-values=>['Buy','Sell'], -default=>['Buy'],-columns=>2,-rows=>1), p,
    hidden(-name=>'run', -default=>['1']), hidden(-name=>'portfolio_name',-default=>[$portfolio]),
    hidden(-name=>'act', -default=>['portfolio-transaction']),
    submit,
    end_form, hr;
  }
  else {
    my $portfolio_name = param('portfolio_name');
    my $symbol=param('stock_symbol');
    $symbol=uc($symbol);
    my $port = $portfolioID;
    my $quantity=param('quantity');
    my $direction=param('direction');
    my $logStr;
    if ($direction eq 'Sell')
    {
      $logStr=StockSell($port,$symbol,$quantity);
      print h2($logStr);

    }
    if ($direction eq 'Buy')
    {
     $logStr=StockBuy($port,$symbol,$quantity);
     print h2($logStr);
    }
    # if ($error) {
    #  print "Couldn't create portfolio because: $error";
    # }
    # else {
    #   print "Portfolio $portfolio_name was successfully created! Go <a href=\"portfolio.pl\">here</a> to view your new portfolio.";
    # }
  }
}


#
#
# NEAR
#
#
# Nearby committees, candidates, individuals, and opinions
#
#

# Note that the individual data should integrate the FEC data and the more
# precise crowd-sourced location data.   The opinion data is completely crowd-sourced
#
# This form intentionally avoids decoration since the expectation is that
# the client-side javascript will invoke it to get raw data for overlaying on the map
#
#
if ($action eq "near") {
  my $latne = param("latne");
  my $longne = param("longne");
  my $latsw = param("latsw");
  my $longsw = param("longsw");
  my $whatparam = param("what");
  my $format = param("format");
  my $cycle = param("cycle");
  my %what;
  
  $format = "table" if !defined($format);
  #select distinct cycle from cs339.committee_master where cycle in ('1112','0506');
  $cycle = "'1112'" if !defined($cycle);

  if (!defined($whatparam) || $whatparam eq "all") { 
    %what = ( committees => 1, 
	      candidates => 1,
	      individuals =>1,
	      opinions => 1);
  } else {
    map {$what{$_}=1} split(/\s*,\s*/,$whatparam);
  }
	       

  if ($what{committees}) { 
    my ($str,$error) = Committees($latne,$longne,$latsw,$longsw,$cycle,$format);
    if (!$error) {
      if ($format eq "table") { 
	print "<h2>Nearby committees</h2>$str";
      } else {
	print $str;
      }
    }
  }
  if ($what{candidates}) {
    my ($str,$error) = Candidates($latne,$longne,$latsw,$longsw,$cycle,$format);
    if (!$error) {
      if ($format eq "table") { 
	print "<h2>Nearby candidates</h2>$str";
      } else {
	print $str;
      }
    }
  }
  if ($what{individuals}) {
    my ($str,$error) = Individuals($latne,$longne,$latsw,$longsw,$cycle,$format);
    if (!$error) {
      if ($format eq "table") { 
	print "<h2>Nearby individuals</h2>$str";
      } else {
	print $str;
      }
    }
  }
  if ($what{opinions}) {
    my ($str,$error) = Opinions($latne,$longne,$latsw,$longsw,$cycle,$format);
    if (!$error) {
      if ($format eq "table") { 
	print "<h2>Nearby opinions</h2>$str";
      } else {
	print $str;
      }
    }
  }
}

#
# Sign up
#
# User Add functionaltiy 
#
#
#
#
if ($action eq "sign-up") { 
    if (!$run) { 
      print start_form(-name=>'Sign Up'),
	h2('Sign Up'),
	  "Name: ", textfield(-name=>'name'),
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
      my $name=param('name');
      my $email=param('email');
      my $password=param('password');
      my $error;
      $error=UserAdd($name,$password,$email);
      if ($error) { 
	     print "Can't add user because: $error";
      } else {
	     print "$name was successfully signed up! Now <a href=\"portfolio.pl?act=login\">log in to start managing your portfolio!</a>\n";
      }
    }
}

if ($action eq "add-portfolio") {
  if (!$run) {
    print start_form(-name=>'Add Portfolio'),
    h2('Add Portfolio'),
    "Portfolio Name:", textfield(-name=>'portfolio_name'), p,
    "Starting Cash:", textfield(-name=>'cash'), p,
    hidden(-name=>'run', -default=>['1']),
    hidden(-name=>'act', -default=>['add-portfolio']),
    submit,
    end_form, hr;
  }
  else {
    my $portfolio_name = param('portfolio_name');
    my $cash = param('cash');
    my $error;
    $error = PortfolioAdd($portfolio_name, $cash, $email);
    if ($error) {
      print "Couldn't create portfolio because: $error";
    }
    else {
      print "Portfolio $portfolio_name was successfully created! Go <a href=\"portfolio.pl\">here</a> to view your new portfolio.";
    }
  }
}

#
# Debugging output is the last thing we show, if it is set
#
#

print "</center>" if !$debug;

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
  print "</div>";

print end_html;

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
  eval { @rows = ExecSQL($dbuser,$dbpasswd, "select name, email from Users order by name"); }; 
  if ($@) { 
    return (undef,$@);
  } else {
    return (MakeTable("user_table",
		      "2D",
		     ["Name", "Email"],
		     @rows),$@);
  }
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
    ExecStockSQL("ROW", "insert into portfolios (PortfolioId, UserId, cash) values (?,?,?)", @_);
  };
  return $@;
}

sub GetPortfolios {
	my $userID = @_;
  my @rows;
  eval {
    @rows = ExecStockSQL("ROW", "select PortfolioId from portfolios where UserID=? ", $userID);
  };
  return @rows;
}



sub GetPortUser{
	my $port = @_;
	my $user;
	eval { $user = ExecStockSQL("ROW", "select UserID from Portfolios where PortfolioID = ?",$port);};
	return ($user,$@);
}

sub GetPortName{
	my $port = @_;
	my $name;
	eval { $name = ExecStockSQL("ROW","select PortfolioName from Portfolios where PortfolioID = ?",$port);};
	return ($name,$@);
}



#use in view transfer history page
sub GetTransHistory {
	my($portfolioID)=@_;
	my @record;
	eval { @record = ExecStockSQL("2D","select TimeStamp, Symbol, TransactionType, Amount from Transactions where PortfolioID=?",$portfolioID);};
	if($@){
		return (undef,$@);
		}
	return (MakeTable("record-table","2D",
			  ["TimeStamp","Symbol","TransactionType","Amount"],
			  @record),$@);
}


sub TransferMoney{
	my ($portID,$portname,$action,$user,$amount)=@_;
#	print "action is $action and amount is $amount.";
	if($action eq 'Withdraw')
	{
#		print "are you here";
		$amount = -$amount;
	}
	if($action eq 'DEPOSIT'){
#		print"action is right and amount is $amount";
		$amount = $amount;
	}
	my @currentcash;
	my $currentcash;
	eval { @currentcash = ExecStockSQL("COL","select Cash from Portfolios where PortfolioID=?",$portID);};
        print "You used to have $currentcash[0]\n";
 	$currentcash[0] += $amount;
	print "And now you have \$ $currentcash[0] cash";
	eval { ExecStockSQL("COL","update Portfolios set Cash=? where PortfolioID=?",$currentcash[0],$portID);};
	return $@;
}


sub StockBuy {
   my ($portfolioid,$symbol,$quantity)=@_;
    my $stockVal = GetLatest($symbol);
    my $action = 'buy';
   #   return $stockVal.' is the current price of '.$symbol;
    #  GetHistory($symbol);
     DotheTrans($portfolioid,$symbol,$quantity,$stockVal,$action);
  # };
}

sub DotheTrans{
	my($portfolioID,$symbol,$quantity,$stockVal,$action)=@_;
	my @currentcash;
	my $currentcash;
	my @currentamount;
	my $currentamount;
	my $time= parsedate("+2 secs");
	eval {@currentcash = ExecStockSQL("COL","select Cash from Portfolios where PortfolioID=?",$portfolioID);};
	eval {@currentamount = ExecStockSQL("COL","select Amount from Holdings where PortfolioID=? and Symbol=?",$portfolioID,$symbol);};
	my $cost = $stockVal * $quantity;
	print "current stock is $stockVal and the amount is $quantity\n";
	if($action eq 'buy'){
		if($currentcash[0]< $cost)
		{
			print "You cannot do this because you don't have enough money";
			return $@;
		}
		else{
			
			$currentcash[0] -= $cost;
			print "cost is $cost and the currentcash left would be $currentcash[0]";
			eval { ExecStockSQL("COL","update Portfolios set Cash=? where PortfolioID=?",$currentcash[0],$portfolioID);};
		#	return $@;
			$currentamount[0] += $quantity;
			if($currentamount[0] == $quantity){
				
				eval { ExecStockSQL("COL","insert into Holdings(PortfolioID,Symbol,Amount) values(?,?,?)",$portfolioID,$symbol,$quantity);};
			}
			else{
				print "current amount is $currentamount[0]";
				eval { ExecStockSQL("COL","update Holdings set Amount=? where PortfolioID=? and Symbol=?",$currentamount[0],$portfolioID,$symbol);};
			}
			eval { ExecStockSQL("COL","insert into Transactions values(?,?,?,'Buy',?)",$portfolioID,$time,$symbol,$quantity);};	
		}
	}
	if($action eq 'sell'){
		if($currentamount[0] < $quantity){
			print " error, there isn's so much stocks for you to sell";
		}
		else{
			$currentamount[0] -= $quantity;
			$currentcash[0] += $cost;
			print "current amount would be $currentamount[0] ad the quantity would be $quantity";
			eval{ ExecStockSQL("COL","update Portfolios set Cash=? where PortfolioID=?",$currentcash[0],$portfolioID);};
			eval{ ExecStockSQL("COL","update Holdings set Amount=? where portfolioID=? and Symbol=?",$currentamount[0],$portfolioID,$symbol);};
			eval{ ExecStockSQL("COL","insert into Transactions values(?,?,?,'Sell',?)",$portfolioID,$time,$symbol,$quantity);};
		}
	}
}
sub StockSell {
    my ($portfolioID,$symbol,$quantity)=@_;
    my  $stockVal=GetLatest($symbol);
    my $action = 'sell';
    DotheTrans($portfolioID,$symbol,$quantity,$stockVal,$action);
  #  my $stockCount=HoldingCount($portfolioID,$symbol);
   # my $retString='';
    # return 'You currently have'.$stockCount.' shares of '.$symbol.' which is currently valued at '.$stockVal.' per share.';
}

sub GetStocks {
  my @rows;
	my $portfolioID = @_;
  eval {
    @rows = ExecStockSQL("COL", "select symbol from holdings where portfolioID = ?", $portfolioID);
  };
  return @rows;
}
sub GetLatest{
  my ($symb)=@_;
  $symb=uc($symb);
  my $stats;
  my @all;
  my @row;
  $stats = `perl quote.pl $symb`; #get all stats

 @all = split(/\n/, $stats);  #split by newlines, put into @all array

 foreach (@all){   #loop once for each item in @all array
       #process data here
    @row = split(/\t/, $_);
    if ( $row[0] eq 'close' && scalar(@row)>1)
    {
      return $row[1];
    }
  }
 return 0;
}



sub GetHistory{
  my ($symb)=@_;
  my $qsymbol;
  my $qdate;
  my $qopen;
  my $qhigh;
  my $qlow;
  my $qclose;
  my $qvolume;
  my $q;
  my $row;
  my $symbol;
  $symb=uc($symb);
  if(!UpToDate($symb) && inSymbs($symb))
  { $q = Finance::QuoteHist::Yahoo->new
      (
       symbols    => $symb,
       start_date => '08/01/2006',
       end_date   => 'today',
      ) or die;
   foreach $row ($q->quotes()) {
       ($qsymbol, $qdate, $qopen, $qhigh, $qlow, $qclose, $qvolume) = @$row;
       $qdate=parsedate($qdate);
       eval{ExecSQL("COL", "insert into new_stocks_daily (symbol, timestamp, open,close, high, low, volume) values (?,?,?,?,?,?,?)","NA", $qsymbol,$qdate,$qopen,$qclose,$qhigh,$qlow,$qvolume);};
   }
  }
}

 sub UpToDate{
my ($symb)=@_;
$symb=uc($symb);
my @col;
eval{@col=ExecSQL("ROW", "select count(*) from new_stocks_daily where symbol=rpad(?,16)","COL",$symb);};
if ($@) { 
    return 0;
  }
  else
  { 
    return $col[0]>0;
}
}
sub inSymbs{
my ($symb)=@_;
$symb=uc($symb);
my @col;
eval{@col=ExecSQL("ROW", "select count(*) from cs339.stockssymbols where symbol=rpad(?,16)","COL",$symb);};
if ($@) { 
    return 0;
  }
  else
  {
    return $col[0]>0;
  }
}

#
# Add a user
# call with name,password,email
#
# returns false on success, error string on failure.
# 
# UserAdd($name,$password,$email)

sub UserAdd { 
  eval { ExecStockSQL(
		 "insert into Users (LastName, FirstName , email, password) values (?,?,?,?)", @_);};
  return $@;
}


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
# $ok = ValidUser($email,$passwd)
#
#
sub ValidUser {
  my ($email,$password)=@_;
  my @count = ExecStockSQL("ROW", "select count(*) from Users where email=? and password=?",$email,$password);
	return $count[0];
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


######################################################################
#
# Nothing important after this
#
######################################################################

# The following is necessary so that DBD::Oracle can
# find its butt
#
BEGIN {
  unless ($ENV{BEGIN_BLOCK}) {
    use Cwd;
    $ENV{ORACLE_BASE}="/raid/oracle11g/app/oracle/product/11.2.0.1.0";
    $ENV{ORACLE_HOME}=$ENV{ORACLE_BASE}."/db_1";
    $ENV{ORACLE_SID}="CS339";
    $ENV{LD_LIBRARY_PATH}=$ENV{ORACLE_HOME}."/lib";
    $ENV{BEGIN_BLOCK} = 1;
    exec 'env',cwd().'/'.$0,@ARGV;
  }
}

