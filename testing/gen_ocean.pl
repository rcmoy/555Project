#!/usr/bin/perl

######################################################################
#############USE AT YOUR OWN RISK#####################################
# the revisions to this code are quick, hasty, and relatively untested
######################################################################
use Env;
################################################################### 
# This is a simple Perl Program in which reads a vector file      #
# specified as ARGV<0> and generates Spectre stimulus from it.    #
# Next it generates an OCEAN script to be run in the Cadence CIW  #
# Ihis OCEAN script will apply the stimulus, simulate the desgin, #
# dump the simulation results to an ASCII file, and finally kick  #
# off check_res.pl.  check_res.pl will check that the resulting   #
# simulation is functionally equivalent to the specified output   #
# in the original vector file.                                    #
###################################################################
$clk2q = 0.140;		## ns from clk posedge to stimulus
$rise_fall = 0.05;	## rise fall time of signals in ns
$PW = 0.075;		## pulse width for pulse latches
$basefile = $ARGV[0];

if ($#ARGV==-1) {
    die "ERROR: Need to specify vector file with stimulus/response\n";
}


if (!($basefile=~/.vec$/)) {
  $infile = $basefile.".vec";
}
else {
  $infile = $basefile;
  ($basefile,$junk) = split(/\./,$infile);
}
open(INFILE,"$infile") || die "ERROR: Can't open $infile for read\n";
open(OUTFILE,">vectors.stim") || die "ERROR: Can't open vectors.stim for write\n";

printf "Enter clock period in MHz: ";
$freq = <STDIN>;

$ln = 0;
while (<INFILE>) {
    chop($_);
    $lines[$ln] = $_;
    $ln++;
}
close(INFILE);

@sigs = split(/\s+/,$lines[0]);
$sig = 0;
while (!($sigs[$sig]=~/-->/)) {
    if ($sigs[$sig]=~/</) {    ### if signal is a vector
      ($base,$rest) = split(/</,$sigs[$sig]);
      ($ui,$li) = split(/:/,$rest);
      chop($li);
      for ($x=$ui; $x>=0; $x--) {
	  $inputs[$sig][$x]=$base."<".$x.">";
	  $input_width[$sig]=$ui-$li+1;
      }
    }
    else {
      $inputs[$sig][0]=$sigs[$sig];
      $input_width[$sig]=1;
    }
    $sig++;
}
$num_inputs = $sig;

print "Inputs Are:\n";
print "------------------------------------------\n";
for ($input=0; $input<$num_inputs; $input++) {
    for ($x=$input_width[$input]-1; $x>=0; $x--) {
	print "$inputs[$input][$x] ";
    }
    print "\n";
}
print "------------------------------------------\n";

##################################################################
## Now parse input vectors and form $sim_val[][] data structure ##
##################################################################
for ($vector=0; $vector<$ln-1; $vector++) {
    @values = split(/ /,$lines[$vector+1]);
    $sig = 0;
    for ($input=0; $input<$num_inputs; $input++) {
	for ($bit=0; $bit<$input_width[$input]; $bit++) {
	    if (!($bit%4)) {
		$hex_nibble = chop($values[$input]);
		$bin_nibble = &bin($hex_nibble);
            }
	    $val = chop($bin_nibble);
	    $stim_val[$vector][$sig]=$val;
            $sig++;
	}
    }
}

#################################################################
## Now print stimulus bit blasted to screen so user can verify ##
#################################################################
$sig = 0;
for ($input=0; $input<$num_inputs; $input++) {
    for ($bits=0; $bits<$input_width[$input]; $bits++) { 
      printf "$inputs[$input][$bits]";
      for ($vector=0; $vector<$ln-1; $vector++) {
  	printf " $stim_val[$vector][$sig]";
      }
      printf "\n";
      $sig++;
    }
}

###########################
## Now generate Stimulus ##
###########################
$sig = 0;
$period = 1000/$freq;	## cast from freq in MHz to period in ns
$half_period = $period/2;
##printf OUTFILE "vclk clk 0 pulse 0 1.8 %1.2fns %1.2fns %1.2fns %1.2fns %1.2fns\n",$half_period,$rise_fall,$rise_fall,$half_period-$rise_fall,$period;
printf OUTFILE "vclk clk 0 pulse 0 1.8 %1.2fns %1.2fns %1.2fns %1.2fns %1.2fns\n",$half_period,$rise_fall,$rise_fall,$PW,$period;
##printf OUTFILE "vvdd vdd! 0 dc 1.8\n";
##printf OUTFILE "vvss vss! 0 dc 0\n";
for ($input=0; $input<$num_inputs; $input++) {
    for ($bits=0; $bits<$input_width[$input]; $bits++) { 
      printf OUTFILE "v$inputs[$input][$bits] $inputs[$input][$bits] 0 pwl 0n ";
      if ($stim_val[0][$sig]=~/1/) {
	  printf OUTFILE "1.8";
	  $last_val = 1;
      }
      else {
	  printf OUTFILE "0";
	  $last_val = 0;
      }
      $time = $half_period+$clk2q;
      for ($vector=1; $vector<$ln-1; $vector++) {
	if ($stim_val[$vector][$sig]=~/1/) {
	    $this_val = 1;
	}
	else {
	    $this_val = 0;
	}
	if ($this_val != $last_val) {
  	  printf OUTFILE " %fn ",$time;
	  if ($last_val) {
	    printf OUTFILE "1.8";
	  }
  	  else {
	    printf OUTFILE "0";
	  }  
	  printf OUTFILE " %fn ",$time+$rise_fall;
          if ($this_val) {
	    printf OUTFILE "1.8";
	  }
          else {
	    printf OUTFILE "0";
	  }
	  $last_val = $this_val;
	}
	$time+=$period;		## advance time
      }
      printf OUTFILE "\n";
      $sig++;
    }
}
close(OUTFILE);
$duration = ($ln-0.5)/$freq*1000;		## form run duration in ns

##############################################################
# To generate OCEAN script will need list of outputs to save #
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

$modelfile = $HOME."\/ece555\/cadence\/modelfile18";

if (!(-e $modelfile)) {
    printf "ERROR: Expecting to find file $modelfile\n";
    exit(1);
}


### Now generate ocean script ####
open(OCN,">run_and_check.ocn") || die "ERROR: Don\'t have write permissions in $PWD\n";

printf OCN "simulator( \'spectre )\n";
printf OCN "design( \"%s/cadence/simulation/%s/spectre/schematic/netlist/netlist\")\n",$HOME,$basefile;
printf OCN "resultsDir( \"%s/cadence/simulation/%s/spectre/schematic\")\n",$HOME;
printf OCN "modelFile(\n";
printf OCN "    \'(\"%s/ece555/cadence/modelfile18\" \"\")\n",$HOME;
printf OCN ")\n";
printf OCN "stimulusFile( ?xlate nil\n";
printf OCN "    \"%s/vectors.stim\"\n",$PWD;
printf OCN ")\n";
printf OCN "analysis(\'tran ?stop \"%dn\" ?errpreset \"moderate\" )\n",$duration;
printf OCN "envOption(\n";
printf OCN "\t\t\'analysisOrder list(\"tran\")\n";
printf OCN "\t\t\'switchViewList \'( \"spectre cmos_sch cmos.sch extracted schematic\" )\n";
printf OCN ")\n";
printf OCN "save( \'v \"/clk\"";
for ($output=0; $output<$num_outputs; $output++) {
    for ($x=$output_width[$output]-1; $x>=0; $x--) {
	printf OCN " \"/%s\"",$outputs[$output][$x];
    }
}
printf OCN " \)\n";
printf OCN "save( 'i \"/V0/PLUS\" )\n";
printf OCN "temp( 27 )\n";
printf OCN "createNetlist()\n";
printf OCN "run()\n";
printf OCN "selectResults(\"tran\")\n";
printf OCN "ocnPrint(?output \"cadence/simulation/sim_out.txt\" ?precision 16 ?numberNotation \`scientific v(\"/clk\")";
for ($output=0; $output<$num_outputs; $output++) {
    for ($x=$output_width[$output]-1; $x>=0; $x--) {
	printf OCN " v(\"/%s\")",$outputs[$output][$x];
    }
}
printf OCN " i(\"/V0/PLUS\")";
printf OCN " ?step 0.025n)\n";
printf OCN "id=ipcBeginProcess(\"~ejhoffman\/perl_progs\/check_res.pl %s\")\n",$basefile;
printf OCN "ipcWaitForProcess(id)\n";


close(OCN);

####### Delete result file so an old one sitting around can mess us up #####
$cmd = "rm ".$HOME;
$cmd = $cmd."/cadence/simulation/sim_out.txt";
system($cmd);

printf "\nSimulation needs to run for %d ns\n",$duration;

printf "\nA vector file containing stimulus has been created.\n";
printf "In ADE use: Setup ==> Simulation Files to apply as stimulus\n";
printf "Name of file is: $PWD\/vectors.stim\n";

printf "\nAn OCEAN script has been created.  In the CIW type:\n";
printf "load(\"run_and_check.ocn\")\n";
printf "to run the script\n";

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
