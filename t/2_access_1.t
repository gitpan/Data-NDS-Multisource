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
  my $val = $obj->access(@test);
  return $val;
}

$tests = "
three /a ~ _undef_

three /c ~ 3c

three /b ~ 3b1

four /l ~ 2

";

$obj = new Data::NDS::Multisource "$dir/2_AD.yaml";

print "2: access(scalar context, single name)...\n";
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

