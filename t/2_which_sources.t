#!/usr/bin/perl -w

require 5.001;

$runtests=shift(@ARGV);
if ( -f "t/test.pl" ) {
  require "t/test.pl";
  $dir="t";
} elsif ( -f "test.pl" ) {
  require "test.pl";
  $dir=".";
} else {
  die "ERROR: cannot find test.pl\n";
}

unshift(@INC,$dir);
use Data::NDS::Multisource;

sub test {
  (@test)=@_;
  my $obj = pop(@test);
  return $obj->which_sources(@test);
}

$tests = "
zero /a all ~ 0 1

one /xxx all ~ 0 2

seven /u2 all-val ~ 0 3

seven /o1/3 all ~ 0 -1

eight /c all ~ 1 source1 source2

eight /c all-val ~ 1 source1

eight /c readonly ~ 1 source1 source2

eight /c readonly-val ~ 1 source1

eight /c writable ~ 0 0

eight /c writable-val ~ 0 0

eight /x0 all-val ~ 1 source1 source2

";

$obj = new Data::NDS::Multisource "$dir/2_AD.yaml";

print "2: which_sources...\n";
test_Func(\&test,$tests,$runtests,$obj);

1;

# Local Variables:
# mode: cperl
# indent-tabs-mode: nil
# cperl-indent-level: 3
# cperl-continued-statement-offset: 2
# cperl-continued-brace-offset: 0
# cperl-brace-offset: 0
# cperl-brace-imaginary-offset: 0
# cperl-label-offset: -2
# End:

