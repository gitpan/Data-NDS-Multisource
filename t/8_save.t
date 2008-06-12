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
  }
}

%add = (
  "two" => { a  => { aa1 => aa1v },
             b  => { bb1 => bb1v },
             c  => { cc1 => cc1v } },
);

$tests = "
eles ~ one two

access two /a/aa1 ~ aa1v

";

use File::Copy;
copy("$dir/8_Source1.yaml.orig","$dir/8_Source1.yaml")  or  die "Copy failed: $!";
copy("$dir/8_Source2.yaml.orig","$dir/8_Source2.yaml")  or  die "Copy failed: $!";

$obj = new Data::NDS::Multisource "$dir/8_AD.yaml";
$obj->add("two",$add{"two"});
$obj->save();

$obj = new Data::NDS::Multisource "$dir/8_AD.yaml";

print "8: save...\n";
test_Func(\&test,$tests,$runtests,$obj);

unlink("$dir/8_Source1.yaml.bak","$dir/8_Source2.yaml.bak",
       "$dir/8_Source1.yaml","$dir/8_Source2.yaml");

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

