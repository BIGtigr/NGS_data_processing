#!/usr/bin/perl
# Extract alignments according to given fastq file. 
# Use -maxmismatchN [0|-1] to control maximum mismatch number allowed. 
# For mismatch calculation : 
#   Cigars [HSIDX] are all considered as mismatches. 
#   Because I use hisat2, so 'XM:i:n' is also considered. 
#
use strict; 
use warnings; 
use fileSunhh; 
use mathSunhh; 
use SeqAlnSunhh; 
use LogInforSunhh; 
use Getopt::Long; 
my %opts; 
GetOptions(\%opts, 
	"help!", 
	"inSam1:s", 
	"inFq1:s@", "inFq1_isList!", 
	"fmtSam1:s", 
	"outSam1:s", 
	"maxmismatchN:i", 

	"verbose!", 

	"exe_samtools:s", # samtools 
	"exe_perl:s", # perl 

); 

my $help_txt = <<HH; 

perl $0 -inSam1 in_toRef1.sam   -inFq1 in_src.fq [ -inFq1 in_src_2.fq ... ]

-outSam1      [<STDOUT>] output to STDOUT if not given. Only when given filename as 'out.bam', I will output bam format. Otherwise, output sam format. 

-fmtSam1      ['sam' or detected]
-maxmismatchN [-1] -1 means no filter for 'maxmismatchN'. set as '0' if want no-mismatch alignments. 

-exe_samtools ['samtools']
-exe_perl     ['perl']

-inFq1_isList [Boolean] Input -inFq1 is a ID list instead of fastq format. 

-help         [Boolean]

HH

$opts{'help'} and &LogInforSunhh::usage($help_txt); 

my %cnt; 

&prepare_input(); # outSam1_fh

my %rd_info = %{ &load_fqID_toHash( $opts{'inFq1'} ) }; 
# $cnt{'inRdNum'} = scalar(@{$rd_info{'map_idx'}}); 
$cnt{'inRdNum'} = $rd_info{'rdNum'}; 
$opts{'verbose'} and &tsmsg("[Msg] inFq1 reads number : $cnt{'inRdNum'}\n"); 
&outSam_byRdID( $opts{'inSam1'}, $opts{'fmtSam1'}, $opts{'outSam1_fh'}, \%rd_info ); 
close($opts{'outSam1_fh'}); 

&tsmsg("[Rec] script [$0] done.\n"); 

sub outSam_byRdID {
	my ( $fnSam, $fmtSam, $outFh, $rd_info_h ) = @_; 
	$opts{'verbose'} and &tsmsg("[Msg] Processing sam file [$fnSam]\n"); 
	my %flag_aln    = %{ &SeqAlnSunhh::mk_flag( 'keep' => '0=0,2=0;0=1,2=0,6=1,7=0;0=1,2=0,6=0,7=1' ) }; 

	my $fhSam = &SeqAlnSunhh::openSam( $fnSam, $fmtSam, { 'wiH'=>1, 'verbose'=>$opts{'verbose'}, 'exe_samtools'=>$opts{'exe_samtools'} } ); 
	
	my %tmp_cnt = ('cntN_step'=>5e6); 
	while ( &wantLineC($fhSam) ) {
		&fileSunhh::log_section($., \%tmp_cnt) and &tsmsg("[Msg]   Processing $. line.\n"); 
		m/^\@/ and do { print {$outFh} "$_\n" ;  next; }; 
		my @ta = &splitL("\t", $_); 
		defined $rd_info_h->{'ID2idx'}{$ta[0]} or next; 
		defined $flag_aln{$ta[1]} or next; 
		if ( $opts{'maxmismatchN'} >= 0 ) {
			my $cnt_mismat = &SeqAlnSunhh::cnt_sam_mismatch(\@ta, 'set_rna'); 
			$cnt_mismat <= $opts{'maxmismatchN'} or next; 
		}

		print {$outFh} "$_\n"; 
	}

	return; 
}# sub outSam_byRdID() 

sub load_fqID_toHash {
	my $cnt = -1; 
	my %back_hash; 
#	my @back_id; 
	for my $fn (@{$_[0]}) {
		$opts{'verbose'} and &tsmsg("[Msg] Loading fq file [$fn] start.\n"); 
		my $fh = &openFH( $fn, '<' ) or &stopErr("[Err] Failed to open file [$fn]\n"); 
		if ($opts{'inFq1_isList'}) {
			while (&wantLineC($fh)) {
				$_ =~ m/^(\S+)/ or &stopErr("[Err] Bad ID [$_]!\n"); 
				$cnt ++; 
				$back_hash{$1} = $cnt; 
			}
		} else {
			while (<$fh>) {
				m/^\@(\S+)/ or &stopErr("[Err] Bad ID!\n"); 
				$cnt ++; 
#				push(@back_id, [0,0,0,0,$1]); 
				$back_hash{$1} = $cnt; 
				<$fh>; <$fh>; <$fh>; 
			}
		}
		close($fh); 
		$opts{'verbose'} and &tsmsg("[Msg] Loading fq file [$fn] finished.\n"); 
	}
	# return( {'ID2idx' => \%back_hash}, 'map_idx' => [@back_id], 'rdNum' => $cnt ); 
	return( { 'ID2idx' => \%back_hash, 'rdNum' => $cnt } ); 
}# load_fqID_toHash()


sub prepare_input {
	$opts{'exe_samtools'} //= 'samtools'; 
	$opts{'exe_perl'} //= 'perl'; 
	$opts{'maxmismatchN'} //= -1; 
	if ( defined $opts{'outSam1'} ) {
		$opts{'outSam1'} =~ m/\.bam$/ and $opts{'outFmt1'} //= 'bam'; 
		$opts{'outFmt1'} //= 'sam'; 
		if ( $opts{'outFmt1'} eq 'bam' ) {
			my $fh; 
			open($fh, '|-', "$opts{'exe_samtools'} view -bS -o $opts{'outSam1'} -") or &stopErr("[Err] Failed to write as bam.\n"); 
			$opts{'outSam1_fh'} = $fh; 
		} else {
			$opts{'outSam1_fh'} = &openFH( $opts{'outSam1'}, '>' ); 
		}
	} else {
		$opts{'outSam1_fh'} = \*STDOUT; 
	}
	( defined $opts{'inSam1'} ) or &stopErr("[Err] Need -inSam1\n"); 
	defined $opts{'inFq1'} or &stopErr("[Err] Need -inFq1\n"); 
	if (defined $opts{'fmtSam1'}) {
		$opts{'fmtSam1'} = lc($opts{'fmtSam1'}); 
		$opts{'fmtSam1'} =~ m/^(sam|bam)$/ or &stopErr("[Err] bad -fmtSam1 $opts{'fmtSam1'}\n"); 
	} else {
		$opts{'inSam1'} =~ m/\.(bam|sam)$/i and $opts{'fmtSam1'} = lc($1); 
	}
	$opts{'fmtSam1'} //= 'sam'; 
	$opts{'verbose'} and &tsmsg("[Msg] Set : -fmtSam1 $opts{'fmtSam1'}\n"); 
	
	return; 
}# sub prepare_input() 



