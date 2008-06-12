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
  my $op  = shift(@test);
  my $obj = pop(@test);

  if ($op eq "eles") {
     return $obj->eles(@test);

  } elsif ($op eq "access") {
     $ret = $obj->access(@test);
     return $ret;

  } elsif ($op eq "add") {
     $ele = shift(@test);
     $val = $add{$ele};
     return $obj->add($ele,$val);
  }
}

%add = (
  "one" => { a  => { aa1 => newaa1v } },
  "two" => { a  => { aa1 => aa1v },
             b  => { bb1 => bb1v },
             c  => { cc1 => cc1v } },
  "xxx" => { a  => [ 1,2 ] },
);

$tests = "
eles ~ one

access one /a/a1 ~ a1v

access two /a/aa1 ~ _undef_

add one ~ 1

add xxx ~ 2

add two ~ 0

eles ~ one two

access two /a/aa1 ~ aa1v

";

$obj = new Data::NDS::Multisource "$dir/7_AD.yaml";

print "7: add...\n";
print "   Warnings are expected\n";
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

