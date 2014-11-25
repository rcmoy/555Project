#!/usr/bin/perl

######################################################################
#############USE AT YOUR OWN RISK#####################################
# the revisions to this code are quick, hasty, and relatively untested
######################################################################
use Env;
################################################################### 
# This is a simple Perl Program in which reads a sim_out.txt file #
# dumped by an ocean script after a spectre simulation.           #
# It also reads the .vec file that has the expected response      #
# it compares the waveforms and returns mismatches if any         #
###################################################################
$sw_thres = .9;		## typically VDD/2

$infile = $ARGV[0];
if (!($infile=~/.vec$/)) {
  $infile = $infile.".vec";
}
open(INFILE,"$infile") || die "ERROR: Can't open $infile for read\n";

$ln = 0;
while (<INFILE>) {
    chop($_);
    $lines[$ln] = $_;
    $ln++;
}
$num_vectors = $ln-1;
close(INFILE);

($junk,$outs) = split(/\s+-->\s+/,$lines[0]);

@ins = split(/\s+/,$junk);
$num_ins = $#ins+1;
@sigs = split(/\s+/,$outs);
$sig = 0;
foreach $name (@sigs) {
    if ($name=~/</) {    ### if signal is a vector
      ($base,$rest) = split(/</,$sigs[$sig]);
      ($ui,$li) = split(/:/,$rest);
      chop($li);
      for ($x=$ui; $x>=0; $x--) {
	  $outputs[$sig][$x]=$base."<".$x.">";
      }
      $output_width[$sig]=$ui-$li+1;
    }
    else {
      $outputs[$sig][0]=$name;
      $output_width[$sig]=1;
    }
    $sig++;
}
$num_outputs = $sig;

print "Outputs Are:\n";
print "------------------------------------------\n";
for ($output=0; $output<$num_outputs; $output++) {
    for ($x=$output_width[$output]-1; $x>=0; $x--) {
	print "$outputs[$output][$x] ";
    }
    print "\n";
}
print "------------------------------------------\n";

##################################################################
## Now parse input vectors and form $sim_val[][] data structure ##
##################################################################
for ($vector=0; $vector<$num_vectors; $vector++) {
    @values = split(/ /,$lines[$vector+1]);
    $sig = 0;
    for ($output=0; $output<$num_outputs; $output++) {
	for ($bit=0; $bit<$output_width[$output]; $bit++) {
	    if (!($bit%4)) {
		$hex_nibble = chop($values[$output+$num_ins]);
		$bin_nibble = &bin($hex_nibble);
            }
	    $val = chop($bin_nibble);
	    $exp_val[$vector][$sig]=$val;
            $sig++;
	}
    }
}

open(OUTFILE,">check_res.res") || die "Can't open file for output\n";

#############################################################
## Now print expected results to screen so user can verify ##
#############################################################
print "Expected results are:\n";
print OUTFILE "Expected results are:\n";
$sig = 0;
for ($output=0; $output<$num_outputs; $output++) {
    for ($bits=0; $bits<$output_width[$output]; $bits++) { 
      printf "$outputs[$output][$bits]";
      printf OUTFILE "$outputs[$output][$bits]";
      for ($vector=0; $vector<$num_vectors; $vector++) {
  	printf " $exp_val[$vector][$sig]";
  	printf OUTFILE " $exp_val[$vector][$sig]";
      }
      printf "\n";
      printf OUTFILE "\n";
      $sig++;
    }
}

###############################################################
# Now read in the sim_out.txt file (results from Spectre sim) #
###############################################################
open(RESFILE,"$HOME/cadence/simulation/sim_out.txt") || die "ERROR: Can't open: ~/cadence/simulation/sim_out.txt for read\n";

$ln = 0;

while (<RESFILE>) {
    $lines[$ln] = $_;
    chop($lines[$ln]);
    $ln++;
}
$num_lines = $ln;

$found = 0;
$ln = 0;
while ((!($lines[$ln]=~/^time/)) && ($ln<$num_lines)) {
    $ln++;
}
if ($ln==$num_lines) {
    printf "ERROR: could not find 'time ' designator in sim_out.txt file\n";
    printf OUTFILE "ERROR: could not find 'time ' designator in sim_out.txt file\n";
    exit(1);
}
else {
    @res_sigs = split(/  +/,$lines[$ln]);
}
$indx = 0;
$clk_indx = 0;
foreach $name (@res_sigs) {
    if ($name=~/^time/) {
    }
    elsif ($name=~/\/clk\"/) {
	print "clock found in column $indx\n";
	print OUTFILE "clock found in column $indx\n";
	$clk_indx = $indx;
    }
    elsif ($name=~/\/V0\/PLUS/) {
 	print "current of V0 found in column $indx\n";
 	print OUTFILE "current of V0 found in column $indx\n";
	$curr_indx = $indx;
    }
    else {
	($junk,$sname) = split(/\//,$name);
	($sname,$junk) = split(/\"/,$sname);
	push(@rnames,$sname);
	$sig_indx{$sname} = $indx;
    }
    $indx++;
}
if ($clk_indx==0) {
    print "ERROR: clk signal not found in Spectre results file...\n";
    print OUTFILE "ERROR: clk signal not found in Spectre results file...\n";
    print "       Simulaiton must have a clock even if your circuit does not\n";
    print OUTFILE "       Simulaiton must have a clock even if your circuit does not\n";
    exit(1);
}

##############################################
# Skip blank lines till waveform data starts #
##############################################
$ln++;
while (!($lines[$ln]=~/0./)) {
    $ln++;
}
$indx = 0;
$last_clk = 1;
$vector = 0;
$miscompares = 0;
$compares = 0;
$integrating = 0;
$charge = 0.0;
print "----------------- Comparing Results -------------------\n";
print OUTFILE "----------------- Comparing Results -------------------\n";
while ($ln<$num_lines) {
    if ($lines[$ln]=~/^\s+/) {
	($junk,$lines[$ln]) = split(/^\s+/,$lines[$ln]);
    }
    @values = split(/\s+/,$lines[$ln]);
    $indx = 0;
    foreach $entry (@values) {
	##########################################
	# scientific notaion to float for values #
	##########################################
	$num_value[$indx] = sprintf("%1.2f",$entry*1.0);
        $indx++;
    }
    if ($integrating) {
	print "curr = $values[$curr_indx]\n";
	$curr_time = $values[0]*1E9;
	$charge = $charge-$values[$curr_indx]*($curr_time-$last_time);
	$last_time = $curr_time;
    }
    if ($num_value[$clk_indx]>$sw_thres) {
	if ($last_clk==0) {
	  if ($integrating==0) {
	    #########################################
	    ## We start integrating current at first clock edge.  Prior to that
	    ## current could have been high due to uninitialized flops 
	    #######################################3
	    $integrating = 1;
	    $last_time = $values[0]*1E9;
	    $first_edge = $last_time;
	  }
	  $compares++;
	  print "Rising clock occurred at time $values[0]\n";
	  print OUTFILE "Rising clock occurred at time $values[0]\n";
	  ###############################################
	  # Now look 2-vectors back and compare results #
	  ###############################################
          @values = split(/\s+/,$lines[$ln-2]);
          $indx = 0;
          foreach $entry (@values) {
    	    ##########################################
	    # scientific notaion to float for values #
	    ##########################################
	    if ($indx) {
	      $num_value[$indx] = sprintf("%3.2f",$entry*1.0);
	    }
	    else {
	      $num_value[$indx] = sprintf("%3.2f",$entry*1000000000);
	    }
            $indx++;
          }
	  foreach $entry (@rnames) {
	      $sig = 0;
	      $comp_found = 0;
	      for ($output=0; $output<$num_outputs; $output++) {
		  for ($bit=0; $bit<$output_width[$output]; $bit++) {
		    if ($outputs[$output][$bit] eq $entry) {
			$comp_found = 1;
		        if (($exp_val[$vector][$sig]=~/1/) && ($num_value[$sig_indx{$entry}]<$sw_thres)) {
			    printf "ERROR: at time %3.2fns (vector %d) signal $entry was expected to be a 1, was %1.2f\n",$num_value[0],$vector,$num_value[$sig_indx{$entry}];
			    printf OUTFILE "ERROR: at time %3.2fns (vector %d) signal $entry was expected to be a 1, was %1.2f\n",$num_value[0],$vector,$num_value[$sig_indx{$entry}];
			    $miscompares++;
			}
			if (($exp_val[$vector][$sig]=~/0/) && ($num_value[$sig_indx{$entry}]>$sw_thres)) {
			    printf "ERROR: at time %3.2fns (vector %d) signal $entry was expected to be a 0, was: %1.2f\n",$num_value[0],$vector,$num_value[$sig_indx{$entry}];
			    printf OUTFILE "ERROR: at time %3.2fns (vector %d) signal $entry was expected to be a 0, was: %1.2f\n",$num_value[0],$vector,$num_value[$sig_indx{$entry}];
			    $miscompares++;
			}
		    }
		    $sig++;
		  }
	      }
	      if (!($comp_found)) {
		  printf "WARNING: comparison not made for signal $entry for this clock edge\n";
		  printf OUTFILE "WARNING: comparison not made for signal $entry for this clock edge\n";
	      }

	  }
	  $vector++;	## move to next vector in expected file
	}
	$last_clk = 1;
    }
    else {
	$last_clk = 0;
    }
     
    $ln++;
}

if ((!($miscompares)) && ($compares>=$num_vectors)) {
    print "YAHOO!!! test passed with no errors\n";
    print OUTFILE "YAHOO!!! test passed with no errors\n";
}
elsif ($compares<$num_vectors) {
    print OUTFILE "Hmmm...I expected more rising clock edges\n";
}

printf "Average current consumption was: %f mA\n",$charge*1000/($last_time - $first_edge);
printf OUTFILE "Average current consumption was: %1.10f mA\n",$charge*1000/($last_time - $first_edge);;

system("xterm -e less check_res.res");


sub bin {
    if ($_[0]=~/0/) { return("0000"); }
    elsif ($_[0]=~/1/) { return("0001"); }
    elsif ($_[0]=~/2/) { return("0010"); }
    elsif ($_[0]=~/3/) { return("0011"); }
    elsif ($_[0]=~/4/) { return("0100"); }
    elsif ($_[0]=~/5/) { return("0101"); }
    elsif ($_[0]=~/6/) { return("0110"); }
    elsif ($_[0]=~/7/) { return("0111"); }
    elsif ($_[0]=~/8/) { return("1000"); }                    
    elsif ($_[0]=~/9/) { return("1001"); }                    
    elsif ($_[0]=~/a/i) { return("1010"); }                  
    elsif ($_[0]=~/b/i) { return("1011"); }                  
    elsif ($_[0]=~/c/i) { return("1100"); }                  
    elsif ($_[0]=~/d/i) { return("1101"); }                  
    elsif ($_[0]=~/e/i) { return("1110"); }                  
    elsif ($_[0]=~/f/i) { return("1111"); }                  
    else {return("xxxx");}                                   
}                                               
