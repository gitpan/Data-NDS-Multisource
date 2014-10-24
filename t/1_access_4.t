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
  (@test)  = @_;
  my $obj  = pop(@test);
  my $path = pop(@test);
  my @val  = $obj->access(\@test,$path);
  return @val;
}

$tests = "
ele2
ele4
/a
~
  ele4
  4a

ele1
ele2
/x/y
~
  ele1
  [ foo, bar ]

ele1
ele2
/t
~
   ele1
   { aa => 11, bb => 22 }

";

$obj = new Data::NDS::Multisource "$dir/1_AD.yaml";

print "1: access(list context, multiple names)...\n";
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

