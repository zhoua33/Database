//
// Global state
//
// map     - the map object
// usermark- marks the user's position on the map
// markers - list of markers on the current map (not including the user position)
// 
//

//
// First time run: request current location, with callback to Start
//
if (navigator.geolocation)  {
    navigator.geolocation.getCurrentPosition(Start);
}


function UpdateMapById(id, tag) {

    var target = document.getElementById(id);
    var data = target.innerHTML;

    var rows  = data.split("\n");
   
    for (i in rows) {
	var cols = rows[i].split("\t");
	var lat = cols[0];
	var long = cols[1];

	markers.push(new google.maps.Marker({ map:map,
						    position: new google.maps.LatLng(lat,long),
						    title: tag+"\n"+cols.join("\n")}));
	
    }
}

function ClearMarkers()
{
    // clear the markers
    while (markers.length>0) { 
	markers.pop().setMap(null);
    }
}


function UpdateMap()
{
 var color = document.getElementById("color");
   var color1 = document.getElementById("committees");
   var color2=document.getElementById("individuals"); 
    color.innerHTML="<b><blink>Updating Display...</blink></b>";
    color.style.backgroundColor='white';
    color1.style.backgroundColor='white';
    color2.style.backgroundColor='white';

    ClearMarkers();

   

   if( document.getElementById("Committee").checked){
    UpdateMapById("committee_data","COMMITTEE");
   // color.innerHTML="Dem Committee uses"+sum1+Ready";
    var sum1= $('#sumVal1').val();
    var sum2= $('#sumVal2').val();
    var sumtotal=parseInt($('#sumtotal').val());
    sumtempt=parseInt(sum1);
    sumtempt2=parseInt(sum2);
  //  var temp1=sumtempt+sumtempt2;
    color1.innerHTML="Total amount is: "+sumtotal+" Dem Committee uses "+sumtempt+" and "+"Rep Committee uses "+sumtempt2;
       if(sumtempt<sumtempt2)
	{color1.style.backgroundColor='red';}
	else{color1.style.backgroundColor='blue';}
	}
   if(document.getElementById("Candidate").checked)
   { UpdateMapById("candidate_data","CANDIDATE");
    color.innerHTML="Ready";

    if (Math.random()>0.5) {
        color.style.backgroundColor='blue';
    } else {
        color.style.backgroundColor='red';
    }}
    if(document.getElementById("Opinion").checked)
    {
       UpdateMapById("opinion_data","OPINION");
       var avg= $('#sumVal5').val();
       var stv= $('#sumVal6').val();
     color.innerHTML="Opinion average:"+avg+"Ready"+"Standard deviation:"+stv;
     }
   if(document.getElementById("Individual").checked)
   {
       UpdateMapById("individual_data", "INDIVIDUAL");
   // UpdateMapById("opinion_data","OPINION");
       var sum3= parseInt($('#sumVal3').val());
       var sum4= parseInt($('#sumVal4').val());
       var sumtotal1=parseInt($('#sumtotal1').val());
    //   var temp=sum3+sum4;
    color2.innerHTML="Total amount is:"+sumtotal1+"  Dem Individual uses "+sum3+" and "+"Rep Individual uses "+sum4;
       if(sum3<sum4)
        {color2.style.backgroundColor='red';}
        else{color2.style.backgroundColor='blue';}
        }

   
  //  color.innerHTML="Ready";
    
  //  if (Math.random()>0.5) { 
//	color.style.backgroundColor='blue';
 //   } else {
//	color.style.backgroundColor='red';
  //  }}

}

function NewData(data)
{
  var target = document.getElementById("data");
  
  target.innerHTML = data;

  UpdateMap();

}

function ViewShift()
{
    var bounds = map.getBounds();

    var ne = bounds.getNorthEast();
    var sw = bounds.getSouthWest();
    
    var color = document.getElementById("color");
    var what  = "";
    if(document.getElementById("Committee").checked) 
     
	what = what + "committees,";
	
    if(document.getElementById("Candidate").checked)
 	what =  what + "candidates,";
    if(document.getElementById("Individual").checked)
	what = what + "individuals,";
    if(document.getElementById("Opinion").checked)
        what = what + "opinions,";
    
    var cycle="";
    
    var i=0;
    
    if(document.getElementById("8990").checked)
	cycle = cycle + "8990,";
    if(document.getElementById("9394").checked)
        cycle = cycle + "9394,";
    if(document.getElementById("9900").checked)
        cycle = cycle + "9900,";
    if(document.getElementById("1112").checked)
        cycle = cycle + "1112,";
    if(document.getElementById("8182").checked)
        cycle = cycle + "8182,";
    if(document.getElementById("9798").checked)
        cycle = cycle + "9798,";
    if(document.getElementById("0304").checked)
        cycle = cycle + "0304,";
    if(document.getElementById("0708").checked)
        cycle = cycle + "0708,";
    if(document.getElementById("1314").checked)
        cycle = cycle + "1314,";
    if(document.getElementById("8586").checked)
        cycle = cycle + "8586,";
    if(document.getElementById("8788").checked)
        cycle = cycle + "8788,";
    if(document.getElementById("0910").checked)
        cycle = cycle + "0919,";
    if(document.getElementById("7980").checked)
        cycle = cycle + "7980,";
    if(document.getElementById("8384").checked)
        cycle = cycle + "8384,";
    if(document.getElementById("9596").checked)
        cycle = cycle + "9596,";
    if(document.getElementById("0102").checked)
        cycle = cycle + "0102,";
    if(document.getElementById("9192").checked)
        cycle = cycle + "9192,";
    if(document.getElementById("0506").checked)
        cycle = cycle + "0506,";


  //  for(i=0;i<chec.length;i++)
   // {
     //    if(chec[i].checked)
//	{	cycle = cycle + chec[i].value+",";}
  //  }
    what = what.substring(0,(what.length - 1));
    color.innerHTML="<b><blink>Querying...("+cycle+","+ne.lat()+","+ne.lng()+") to ("+sw.lat()+","+sw.lng()+")</blink></b>";
    color.style.backgroundColor='white';
   
    // debug status flows through by cookie
    $.get("rwb.pl?act=near&latne="+ne.lat()+"&longne="+ne.lng()+"&latsw="+sw.lat()+"&longsw="+sw.lng()+"&format=raw&what="+what+"&cycle="+cycle, NewData);
}


function Reposition(pos)
{
    var lat=pos.coords.latitude;
    var long=pos.coords.longitude;

    map.setCenter(new google.maps.LatLng(lat,long));
    usermark.setPosition(new google.maps.LatLng(lat,long));
}


function Start(location) 
{
  var lat = location.coords.latitude;
  var long = location.coords.longitude;
  var acc = location.coords.accuracy;
  
  var mapc = $( "#map");

  map = new google.maps.Map(mapc[0], 
			    { zoom:16, 
				center:new google.maps.LatLng(lat,long),
				mapTypeId: google.maps.MapTypeId.HYBRID
				} );

  usermark = new google.maps.Marker({ map:map,
					    position: new google.maps.LatLng(lat,long),
					    title: "You are here"});

  markers = new Array;

  var color = document.getElementById("color");
  color.style.backgroundColor='white';
  color.innerHTML="<b><blink>Waiting for first position</blink></b>";

  google.maps.event.addListener(map,"bounds_changed",ViewShift);
  google.maps.event.addListener(map,"center_changed",ViewShift);
  google.maps.event.addListener(map,"zoom_changed",ViewShift);

  navigator.geolocation.watchPosition(Reposition);

}


