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
  return $obj->path_sources(@test);
}

$tests = "
/ ~ source1 source2

/a ~ source2

/a/b ~ source2

/aa ~ source1 source2

/b ~ source1

/b/c ~ source1

/bb/foo ~ source1 source2

/c ~ source1 source2

";

$obj = new Data::NDS::Multisource "$dir/2_AD.yaml";

print "2: path_sources...\n";
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

