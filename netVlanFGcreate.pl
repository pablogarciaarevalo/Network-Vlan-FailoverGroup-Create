#==================================================================================================#
#                                                                                                  #
#                                     netVlanFGcreate.pl                                           #
#                                                                                                  #
# This script create VLANs & Failover Groups in every nodes in the cluster.                        #
#                                                                                                  #
# Because Cluster Data ONTAP prompt doesn't allow the commands 'network port vlan create' and      #
# 'network interface failover-groups create' with * to create them in every nodes, user can use    #
# this script to create only one VLAN & Failover Group singly asking from menu or create several   #
# at once from a text file with a specific format (per line: '<portName>;<vlan_id>').              #
#                                                                                                  #
# - The network port or ifgrp must exists in every nodes.                                          #
# - The network port or ifgrp mustn't be a data role.                                              #
# - The network port can't have configured an ifgrp on it.                                         #
# - The network port syntax is 'e/a<number><letter>' where 'e' is used for physical ethernet ports #
#   and 'a' for ifgrp, <number> = [0-999], <letter> = is a lowercase letter.                       #
# - The VLAN id can't exist in any node.                                                           #
# - The VLAN id & network port must create the same for every nodes.                               #
# - The VLAN id must be an integer in the range 1..4094.                                           #
# - Every nodes have to be healthy.                                                                #
#                                                                                                  #
# Author: Pablo Garcia Arevalo (Professional Services Consultant at NetApp)                        #
#                                                                                                  #
#==================================================================================================#

use lib "/data/Documents/dev/zapi/netapp-manageability-sdk-5.2/lib/perl/NetApp";
use NaServer;
use NaElement;
use strict;

my $args = $#ARGV + 1;
my ($server, $ipaddr, $user, $passwd, @nodeList, $vlanid, $portName, $failoverGroup);


sub print_usage_and_exit() {
    print("\nUsage: netVlanFGcreate.pl\n");
    print("No arguments needed\n");
    exit (-1);
}

sub numNodesHaveVlan {
	# Return how many nodes have the VLAN id passed as an argument configured
	# Arguments:	[0] VLAN id (integer)
	
	# Define the API query
	my $api = NaElement->new("net-vlan-get-iter");
	
	my $xi1 = new NaElement('query');
	$api->child_add($xi1);
	
	my $xi2 = new NaElement('vlan-info');
	$xi1->child_add($xi2);
	
	$xi2->child_add_string('vlanid',$_[0]);
	$api->child_add_string('tag',"");
	
	# Exec the API call
	my $out = $server->invoke_elem($api);
	
	# Check if the execution was failed
	if ($out->results_status() eq "failed") {
		print($out->results_reason() ."\n");
        exit(-1);
	}
	
	# Return the number of nodes in the cDOT have the vlan $_[0]
	return $out->child_get_int("num-records");
	
 }

sub numNodesHavePort {
	# Return how many nodes in the cDOT have the port passed as an argument
	# Arguments:	[0] Port name (string)

	# Define the API query	
	my $api = NaElement->new("net-port-get-iter");
	
	my $xi1 = new NaElement('query');
	$api->child_add($xi1);
	
	my $xi2 = new NaElement('net-port-info');
	$xi1->child_add($xi2);
	
	$xi2->child_add_string('port',$_[0]);
	$xi2->child_add_string('role','data');
	$api->child_add_string('tag',"");
	
	# Exec the API call
	my $out = $server->invoke_elem($api);
	
	# Check if the execution was failed
	if ($out->results_status() eq "failed") {
		print($out->results_reason() ."\n");
        exit(-1);
	}

	# Return the number of nodes in the cDOT have the port $_[0]
	return $out->child_get_int("num-records");
	
 }

sub numNodesHealthy() {
	# Return how many nodes in the cDOT are healthy
	# Arguments:	<none>

	# Define the API query	
	my $api = new NaElement('system-node-get-iter');

	my $xi1 = new NaElement('query');
	$api->child_add($xi1);

	my $xi2 = new NaElement('node-details-info');
	$xi1->child_add($xi2);

	$xi2->child_add_string('is-node-healthy','true');

	# Exec the API call
	my $out = $server->invoke_elem($api);
	
	# Check if the execution was failed
	if ($out->results_status() eq "failed") {
		print($out->results_reason() ."\n");
        exit(-1);
	}

	# Return the number of nodes in the cDOT have the port $_[0]
	return $out->child_get_int("num-records");

}

sub nodes (){
	# Return a array within the node names of the cDOT
	# Arguments:	<none>

	# Define the array variable 
	my @nodeName;
	
	# Define the API query
	my $api = NaElement->new("system-node-get-iter");

	# Exec the API call
	my $out = $server->invoke_elem($api);
	
	# Check if the execution was failed
	if ($out->results_status() eq "failed") {
		print($out->results_reason() ."\n");
        exit(-1);
	}

	my @nodeList = $out->child_get("attributes-list")->children_get();
	my ($nodeInfo,$i);
	$i = 0;
    foreach $nodeInfo (@nodeList) {
        $nodeName[$i] = $nodeInfo->child_get_string("node");
        $i++;
    }
    
    # Return the node names list
    return @nodeName;
	
}

sub numNodesHaveIfgrp {
	# Return the number of nodes which the port passed as a argument is member of a ifgrp
	# Arguments:	[0] List node name (reference of array), [1] Port name (string)

    # Dereference the array var
    my @nodenames = @{$_[0]};
    
    my $num_nodes = 0;
    # Iterate over each node's info
    foreach (@nodenames) {
		my $myifgrp = member_of_ifgrp($_,$_[1]);
		if ($myifgrp ne "") {
			$num_nodes++;
		}
	}

	return $num_nodes;
}

sub member_of_ifgrp {
	# For the port of the node that is a member of an interface group (ifgrp), return the name of the ifgrp
	# Arguments:	[0] Node name (string) [1], Port name (string)

	# Define the API query	
	my $api = new NaElement('net-port-get');
	$api->child_add_string('node',$_[0]);
	$api->child_add_string('port',$_[1]);
	
	# Exec the API call
	my $out = $server->invoke_elem($api);
	
	# Check if the execution was failed
	if ($out->results_status() eq "failed") {
		print($out->results_reason() ."\n");
        exit(-1);
	}

	# Get the attribute needed
	my $myattrib = $out->child_get("attributes");
	my $netportinfo = $myattrib->child_get("net-port-info");
	my $ifgrpString = "";
	$ifgrpString = $netportinfo->child_get_string("ifgrp-port");
	
	# Return the name of the ifgrp
	return $ifgrpString;
	
}

sub numNodesHaveFG {
	# Return how many nodes have a Failover Group with the Failover group name passed as an argument
	# arguments:	[0] Failover group name (string)

	# Define the API query	
	my $api = new NaElement('net-failover-group-get-iter');

	my $xi1 = new NaElement('query');
	$api->child_add($xi1);

	my $xi2 = new NaElement('net-failover-group-info');
	$xi1->child_add($xi2);

	$xi2->child_add_string('failover-group',"$_[0]");

	# Exec the API call
	my $out = $server->invoke_elem($api);
	
	# Check if the execution was failed
	if ($out->results_status() eq "failed") {
		print($out->results_reason() ."\n");
        exit(-1);
	}

	# Return the number of nodes in the cDOT have the port $_[0]
	return $out->child_get_int("num-records");

}

sub netVlanFGcreate {
    # Create the VLAN & Failover Group on the port passed as an arguments in every nodes in the cDOT
    # Arguments:	[0] List node name (reference of array), [1] Port name (string), [2] VLAN id (string), [3] Failover Group name (string)

     # Dereference the array var
    my @nodenames = @{$_[0]};
 
	# Check info
	if ($_[1] !~ m/^(a|e)\d{1,3}[a-z]{1}$/) {
		print "Sorry, the port name $_[1] isn't allowed in cDOT. The port syntax is e/a<number><letter> where 'e' is used ";
		print "for physical ethernet ports and 'a' for ifgrp, <number> = [0-999], <letter> = is a lowercase letter.\n"; }
	elsif ((1 > $_[2]) or ($_[2] > 4094) or ($_[2] !~ m/^[1-9]{1}[0-9]{0,3}$/)) {
		print "Sorry, the VLAN id $_[2] must bpere an integer in the range 1..4094.\n"; }
	elsif (numNodesHealthy != $#nodenames+1) {
		print "Sorry, at least one node isn't healthy.\n"; }
	elsif (numNodesHaveVlan($_[2]) != 0) { 
		print "Sorry, at least one node have already defined the VLAN $_[2].\n"; }
	elsif (numNodesHavePort($_[1]) != $#nodenames+1) {
		print "Sorry, at least one node haven't configured the port/ifgrp $_[1] or the port $_[1] isn't a data role.\n"; }
	elsif (numNodesHaveIfgrp(\@nodeList, $_[1]) != 0) {
		print "Sorry, at least one node have configured an ifgrp on the port $_[1].\n"; }
	elsif (numNodesHaveFG($_[3]) != 0) {
		print "Sorry, at least one node have configured the Failover Group $_[3].\n"; }
	else { 
		# Iterate over each node's info
		foreach (@nodenames) {
		
			# Define another API query to create the VLAN
			my $api = new NaElement('net-vlan-create');
			my $xi = new NaElement('vlan-info');
			$api->child_add($xi);

			# Add the node name, port name & VLAN id info to the query
			$xi->child_add_string('node',$_);
			$xi->child_add_string('parent-interface',$_[1]);
			$xi->child_add_string('vlanid',$_[2]);

			# Exec the API call
			my $xo = $server->invoke_elem($api);
		
			# Check if the execution was failed or print the successfully task
			if ($xo->results_status() eq 'failed') {
				print 'Error:\n';
				print $xo->sprintf();
				exit 1;
			}
		}
	
		print "VLAN $_[1]-$_[2] created successfully in every nodes.\n";

		# IMPORTANT: It runs the command 'net int failover-groups create...' using sshpass because the API doesn't yet have the 'net-failover-group-create' call
    
		# Iterate over each node's info
		foreach (@nodenames) {
			system ("sshpass -p $passwd ssh $user\@$ipaddr net int failover-groups create -failover-group $_[3] -node $_ -port $_[1]-$_[2] >/dev/null");
		}    

		# IMPORTANT: Instead of API call this function check the failover was created successfully

		# Return the number of nodes in the cDOT have the Failover Group $_[2]
	
		if (numNodesHaveFG($_[3]) == $#nodenames+1) {
			print "Failover group $_[3] created successfully in every nodes.\n"; }
		else { 
			print "It was an issue creating Failover Groups $_[3]. Please chech manually.\n"; }

	}

}

sub netVlanFGcreateManually () {
	# Second level menu to create one VLAN id & one Failover Group from input keyboard
	# Arguments:	<none>

    # Define the variable to read the option
    my $continue;
    
    do {
    
		$continue = "";
		print "\nEnter the network interface:";
		chop($portName=<STDIN>);
        
		print "Enter the VLAN id:";
		chop($vlanid=<STDIN>);    

		print "Enter the Failover Group name [vlan-$vlanid]:";
		chop($failoverGroup=<STDIN>);    
		if ($failoverGroup eq "") { $failoverGroup= "vlan-$vlanid";}	
		print "\n";
    
		netVlanFGcreate(\@nodeList, $portName, $vlanid, $failoverGroup);
		
		do {
			print "\nDo you want to create another VLAN & Failover group (y/n)?:";
			chop($continue=<STDIN>);
		} until (($continue eq 'y') or ($continue eq 'Y') or ($continue eq 'n') or ($continue eq 'N'));
		
		
	} until (($continue eq 'n') or ($continue eq 'N'));

	main_menu();

}

sub netVlanFGcreateFromFile () {
	# Second level menu to create one or more VLAN ids & Failover Groups from input file
	# Arguments:	<none>

	print "\The text file must have the specific format per line: '<portName>;<vlan_id>[;FailoverGroup]'.\n";
	print "Please enter the path file to parse:";
	chop(my $pathFile=<STDIN>);
	print "\n";

	open my $file, $pathFile or die "Could not open $pathFile: $!";
	
	while(my $line = <$file>)  {   
		chomp $line;
		my ($myPort, $myVlan, $myFG) = split(';',$line, 3);
		if ($myFG eq "") { $myFG = "vlan-$myVlan"; }

		if ($myPort eq $line) {
			print "The line $line isn't valid because there isn't a ';'.\n"; }
		elsif ($myPort !~ m/^(a|e)\d{1,3}[a-z]{1}$/) {
			print "The line $line isn't valid because the port name $myPort isn't allowed in cDOT.\n"; }
		elsif ((1 > $myVlan) or ($myVlan > 4094) or ($myVlan !~ m/^[1-9]{1}[0-9]{0,3}$/)) {
			print "The line $line isn't valid because the VLAN id $myVlan must be an integer in the range 1..4094.\n"; }
		else {
			netVlanFGcreate(\@nodeList, $myPort, $myVlan, $myFG);
		}
		print "\n";
	}

	close $file;
	main_menu();

}

sub main_menu() {
	# Main menu with the different options
	# Arguments:	<none>

	# Define the variable to read the option
	my $mainOption = "";

	# Looping till a correct option
	do {
		print "\nPlease choose an option:\n";
		print "1) Create a VLAN & Failover Group typing the info.\n";
		print "2) Create one or more VLAN & Failover Group with a text file.\n";
		print "3) Exit.\n";
		chop($mainOption=<STDIN>);
	} until (($mainOption eq '1') or ($mainOption eq '2') or ($mainOption eq "3"));
			
	if ($mainOption eq '1') {
		netVlanFGcreateManually(); }
	elsif ($mainOption eq '2') {
		netVlanFGcreateFromFile(); }

}


sub main() {

    if ($args > 0) {
        print_usage_and_exit();
    }

    print("---------------------------------------------------------------------------\n");
    print(" This script create VLANs & Failover Groups in every nodes in the cluster. \n");
    print("---------------------------------------------------------------------------\n");
    
    # Get the info for cDOT connection
    print "\nEnter the cluster name or IP address: ";
    chop($ipaddr=<STDIN>); 
    
    print "Enter the user name: ";
    chop($user=<STDIN>); 
    
    print "Enter the password: ";
	system('stty','-echo');
    chop($passwd=<STDIN>);
	system('stty','echo');
    print("\n");
        
    # Set the cDOT connection
    $server = NaServer->new($ipaddr, 1, 15);
    $server->set_style("LOGIN");
    $server->set_admin_user($user, $passwd);
    $server->set_transport_type("HTTP");

	# Define an array var and get a list within the node names of the cDOT
    @nodeList = nodes();

    main_menu();
  
}

main();
