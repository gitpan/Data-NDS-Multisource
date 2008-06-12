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
  return $obj->which(@test);
}

$tests = "
/d _defined_ ~ s3

/z _defined_ ~ s2 s3

/z _nonzero_ ~ s3

/l _empty_ ~ l1 s1 s2 s3

/l _nonempty_ ~ l2 l3 l4

/l _2_ ~ l3 l4

/l _=2_ ~

/l _=3_ ~ l3

/l _>2_ ~ l3 l4

/l _<2_ ~ l2

";

$obj = new Data::NDS::Multisource "$dir/5_AD.yaml";

print "5: which...\n";
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

