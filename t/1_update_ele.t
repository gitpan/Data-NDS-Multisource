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
  (@test) = @_;
  my($ele,$path,$val,$obj) = @test;
  my $val1 = $obj->access($ele,$path);
  my $err  = $obj->update_ele($ele,$path,$val);
  my $val2 = $obj->access($ele,$path);
  return ($val1,$err,$val2);
}

$tests = "
ele1 /a 1x ~ 1a 4 1a

ele1 /t 1x ~ _undef_ 3 _undef_

";

$obj = new Data::NDS::Multisource "$dir/1_AD.yaml";

print "1: update_ele...\n";
print "   An invalid structure warning is expected\n";
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

