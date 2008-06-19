package Data::NDS::Multisource;
# Copyright (c) 2007-2008 Sullivan Beck. All rights reserved.
# This program is free software; you can redistribute it and/or modify it
# under the same terms as Perl itself.

###############################################################################
# GLOBAL VARIABLES
###############################################################################

###############################################################################
# TODO
###############################################################################

# Add data validity checkers so that data must pass certain tests.

###############################################################################

require 5.000;
use strict;
use warnings;
use Carp;
use Cwd;
use YAML::Syck;
use Data::NDS;
use File::Basename;
use File::Spec;

use vars qw($VERSION);
$VERSION = "2.02";

###############################################################################
# BASE METHODS
###############################################################################

# The structure of a multisource set is:
#
# $multi =
#   { nds      => Data::NDS object
#     warn     => 0/1
#     file     => MD file
#     list     => 0/1
#     eles     => { NAME_1 => 1, NAME_2 => 1, ... }
#     elesl    => [ NAME_1, NAME_2, ... ]
#     elesd    => 0/1
#     priority => { PATH_1 => [ RULESET, SOURCE_1, SOURCE_2, ... ],
#                   PATH_2 => [ RULESET, SOURCE_1, SOURCE_2, ... ], ... }
#     sources  => { SOURCE_NAME_1 => SOURCE_DESC_1,

#                   SOURCE_NAME_2 => SOURCE_DESC_2, ... }
#     data     => DATA_STRUCTURE
#   }
#
# A source description is a hash:
#   { type     => TYPE
#     writable => 0/1
#     modified => 0/1
#     default  => { order  => [ [ DEFAULT_1, ARGS ... ],
#                               [ DEFAULT_2, ARGS ... ] ... ]
#                   eles   => { DEFAULT_1 => ELE, DEFAULT_2 => ELE, .... } }
#     eles     => { NAME_1 => 1, NAME_2 => 1, ... }
#     elesl    => [ NAME_1, NAME_2, ... ]
#     elesd    => 0/1
#     data     => DATA_STRUCTURE
#     pe       => DATA_STRUCTURE
#   }
#
# DEFAULT_i is one of:
#   [ NDS, RULESET ]
#   [ NDS, RULESET, PATH ]
#   [ NDS, RULESET, PATH, VAL ]
# The RULESET part is optional in all cases. If it is included, it must
# point to a ruleset that has been defined.
#
# DATA_STRUCTURE is either:
#   [ ELE_0, ELE_1, ... ]
# or
#   { NAME_1 => ELE_1, NAME_2 => ELE_2, ... }

sub version {
   my($self) = @_;

   return $VERSION;
}

sub new {
  my($class,$file) = @_;

  my $obj = new Data::NDS;
  my $self = {
              "nds"       => $obj,
              "warn"      => 0,
              "file"      => "",
              "list"      => "",
              "eles"      => {},
              "elesl"     => [],
              "elesd"     => 0,
              "priority"  => {},
              "sources"   => {},
              "data"      => undef,
             };
  if ($file) {
     init($self,$file);
  }
  bless $self, $class;

  return $self;
}

sub warnings {
   my($self,$val) = @_;

   $$self{"warn"} = $val;
   my $obj = $$self{"nds"};
   $obj->warnings($val);
}

sub sources {
   my($self) = @_;

   return sort(keys %{ $$self{"sources"} });
}

sub nds {
   my($self) = @_;
   return $$self{"nds"};
}

###############################################################################
# INIT METHOD
###############################################################################

sub init {
   my($self,$file) = @_;

   if ($$self{"file"}) {
      _Error("[init] Multisource description file already set",
             1,$$self{"file"},0,0,1);
   }

   if (! -f $file) {
      _Error("[init] File not found",1,$file,0,0,1);
   }

   #
   # Separate the path and filename. We want to be in the same
   # directory as the file so that the sources can be referenced
   # relative to it.
   #

   my $cwd        = File::Spec->rel2abs(".");
   $file          = File::Spec->rel2abs($file);
   $$self{"file"} = $file;
   my $dir        = dirname($file);
   if (! chdir($dir)) {
      _Error("[init] Unable to access file directory",1,$dir,0,0,1);
   }

   #
   # Read the MD description
   #

   my($md_ref) = YAML::Syck::LoadFile($file);

   if (! exists $$md_ref{"sources"}) {
      _Error("[init] No sources section in MD description",
             1,$file,0,0,1);
   }
   if (! exists $$md_ref{"priority"}) {
      _Error("[init] No priority section in MD description",
             1,$file,0,0,1);
   }

   #
   # MD file: options section
   #

   _md_options($self,$md_ref,$file);

   #
   # MD file: Sources section
   #
   # Read in all the data from the different sources
   #

   foreach my $source (keys %{ $$md_ref{"sources"} }) {
      _read_source($self,$md_ref,$source,$file);
   }

   #
   # Check data consistency (and create the meta description of the
   # data structure). Also move the default structures out of the
   # main data section.
   #

   my $err = 0;
   foreach my $source (keys %{ $$self{"sources"} }) {
      $err += _check_structure($self,$source);
      $err += _check_defaults($self,$source);
   }
   if ($err) {
      _Error("[init] Error(s) encountered",1,0,0,0,1);
   }

   #
   # MD file: merge section
   #

   _md_priority($self,$md_ref,$file);

   #
   # Check data integrity.
   #

   if ($$self{"warn"}) {
      _check_data_integrity($self);
   }

   chdir($cwd);
}

# Read a single data source.
#
sub _read_source {
   my($self,$md_ref,$source,$file) = @_;

   $$self{"sources"}{$source} =
     { "type"     => "",
       "writable" => 1,
       "modified" => 0,
       "default"  => { "order" => [], "eles" => {} },
       "eles"     => {},
       "elesl"    => [],
       "elesd"    => 0,
       "data"     => undef,
       "pe"       => undef,
     };

   #
   # Read the description
   #

   if (! exists $$md_ref{"sources"}{$source}{"type"}) {
      _Error("[init] Source invalid due to missing type",
             1,$file,$source,0,1);
   }
   my($type) = $$md_ref{"sources"}{$source}{"type"};
   $$self{"sources"}{$source}{"type"} = $type;

   if (exists $$md_ref{"sources"}{$source}{"write"}) {
      $$self{"sources"}{$source}{"writable"} =
        $$md_ref{"sources"}{$source}{"write"};
   }

   #
   # Read the data source
   #

   if ($type eq "yaml") {
      $$self{"sources"}{$source}{"data"} =
        _init_yaml($self,$source,$file,$$md_ref{"sources"}{$source});

   } else {
      _Error("[init] Invalid source type",1,$file,$source,$type,1);
   }

   #
   # All data sources must be either hashes or lists.
   #

   if ($$self{"list"} eq "") {
      if (ref($$self{"sources"}{$source}{"data"}) eq "HASH") {
         $$self{"list"} = 0;
      } else {
         $$self{"list"} = 1;
      }
   } else {
      if (ref($$self{"sources"}{$source}{"data"}) eq "HASH") {
         if ($$self{"list"} == 1) {
            _Error("[init] Data sources must all be lists",
                   1,$file,$source,0,1);
         }
      } else {
         if ($$self{"list"} == 0) {
            _Error("[init] Data sources must all be hashes",
                   1,$file,$source,0,1);
         }
      }
   }

   #
   # Handle defaults (just store them in the data source in the MD
   # for now... we'll actually store them in a separate part of the
   # MD when we check the data for consistency since we want to
   # check the defaults in the same way).
   #

   if (exists $$md_ref{"sources"}{$source}{"default"}) {
      my @def = @{ $$md_ref{"sources"}{$source}{"default"} };
      $$self{"sources"}{$source}{"default"}{"order"} = [ @def ];
   }
}

# Read a YAML data source.
#
sub _init_yaml {
   my($self,$source,$md_file,$source_desc) = @_;

   if (! exists $$source_desc{"file"}) {
      _Error("[init] YAML source requires file",1,$md_file,$source,0,1);
   }
   my($file) = File::Spec->rel2abs($$source_desc{"file"});
   if (! -f $file) {
      _Error("[init] YAML source file not found",1,$file,$source,0,1);
   }
   $$self{"sources"}{$source}{"file"} = $file;

   return YAML::Syck::LoadFile($file);
}

# Parse the options section of the MD file.
#
sub _md_options {
   my($self,$md_ref,$file) = @_;

   return  if (! exists $$md_ref{"options"});
   my @lines = @{ $$md_ref{"options"} };

   my $obj   = $$self{"nds"};
   my $error = 0;

   foreach my $line (@lines) {
      my($opt,@val) = split(/\s+/,$line);

      if ($opt eq "merge_hash"   ||
          $opt eq "merge_ol"     ||
          $opt eq "merge_ul"     ||
          $opt eq "merge_scalar" ||
          $opt eq "merge") {

         my($err) = $obj->set_merge($opt,@val);
         if ($err) {
            _Error("[init] Invalid option in MD description",
                   1,$file,$opt,$err,0);
            $error = 1;
         }

      } elsif ($opt eq "ordered"       ||
               $opt eq "uniform_hash"  ||
               $opt eq "uniform_ul"    ||
               $opt eq "uniform") {

         my($err) = $obj->set_structure($opt,@val);
         if ($err) {
            _Error("[init] Invalid option in MD description",
                   1,$file,$opt,$err,0);
            $error = 1;
         }

      } else {
         _Error("[init] Invalid option in MD description",
                1,$file,$opt,0,0);
         $error = 1;
      }
   }
   if ($error) {
      _Error("[init] Option error(s) encountered",1,0,0,0,1);
   }
}

# Parse the priority section.
#
sub _md_priority {
   my($self,$md_ref,$file) = @_;

   my $obj   = $$self{"nds"};
   my $error = 0;

   foreach my $path (keys %{ $$md_ref{"priority"} }) {

      #
      # Check the sources
      #

      my(@source) = split(/\s+/,$$md_ref{"priority"}{$path});
      my $ruleset = "";

      if ($obj->ruleset_valid($source[0])) {
         $ruleset = shift(@source);
      }

      foreach my $source (@source) {
         if (! exists $$self{"sources"}{$source}) {
            _Error("[init] Invalid source in key list",1,$file,$source,0,0);
            $error = 1;
         }
      }

      if (exists $$self{"priority"}{$path}) {
         _Error("[init] Path priority multiply defined",1,$file,$path,0,1);
         $error = 1;
      }

      $$self{"priority"}{$path} = [ $ruleset, @source ];
   }

   if ($error) {
      _Error("[init] Priority error(s) encountered",1,0,0,0,1);
   }
}

# Check all data elements for structural consistency. Every element
# should have the same data structure.
#
sub _check_structure {
   my($self,$source) = @_;
   my($return) = 0;

   my $obj  = $$self{"nds"};
   my $data = $$self{"sources"}{$source}{"data"};

   if ($$self{"list"}) {
      for (my $i=0; $i<=$#$data; $i++) {
         my($err,$val) = $obj->check_structure($$data[$i],1);
         if ($err) {
            _Error("[_check_structure] Data error",1,$source,$i,$val,0);
            $return = 1;
         }
      }

   } else {
      foreach my $key (keys %$data) {
         my($err,$val) = $obj->check_structure($$data{$key},1);
         if ($err) {
            _Error("[_check_structure] Data error",1,$source,$key,$val,0);
            $return = 1;
         }
      }
   }

   return $return;
}

# We also copy the data structures that provide defaults from the
# data key and into the default key.
#
sub _check_defaults {
   my($self,$source) = @_;
   my($return) = 0;

   my $data = $$self{"sources"}{$source}{"data"};
   my $def  = $$self{"sources"}{$source}{"default"}{"order"};
   my $eles = $$self{"sources"}{$source}{"default"}{"eles"};

   # Copy them

   for (my $i=0; $i<=$#$def; $i++) {
      # $$def[$i] => ( DEFAULT_ELEMENT [RULESET] [PATH] [VAL] )
      my $ele = $$def[$i][0];
      if      ($$self{"list"}    &&  defined $$data[$ele]) {
         $$eles{$i} = $$data[$ele];
      } elsif (! $$self{"list"}  &&  exists $$data{$ele}) {
         $$eles{$ele} = $$data{$ele};
      } else {
         _Error("[_check_defaults] Default missing",1,$source,$i,$ele,0);
         $return = 1;
      }
   }

   return $return;
}

# This checks to make sure that all scalars are the same in all data
# sources where they appear.
#
sub _check_data_integrity {
   my($self) = @_;
   my($obj)  = $$self{"nds"};

   # Check every element

   foreach my $ele (eles($self)) {
      my %tmp = ();

      # Check all sources for this element

      foreach my $source (sources($self)) {
         my $pe = _ce_pe_op($self,"pe_value",$source,$ele,"/");
         next   if (! defined $pe);

         # Get a list of all paths to scalars and compare them

         my %pe = $obj->which($pe);
         foreach my $path (sort(CORE::keys %pe)) {

            if (! exists $tmp{$path}) {
               $tmp{$path} = [$source,$pe{$path}];

            } elsif ($pe{$path} ne $tmp{$path}[1]) {
               _Error("[init] Mismatched value",0,$ele,$path,0,0);
               _Error("[init]                 ",0,$tmp{$path}[0],$tmp{$path}[1],
                      0,0);
               _Error("[init]                 ",0,$source,$pe{$path},0,0);
            }
         }
      }
   }
}

###############################################################################
# ELEMENT EXISTANCE METHODS
###############################################################################

# This retuns a list of all elements in all sources
#
sub eles {
   my($self) = @_;

   return @{ $$self{"elesl"} }  if ($$self{"elesd"});

   my @ret = ();
   foreach my $source (keys %{ $$self{"sources"} }) {
      my @eles = eles_in_source($self,$source);
      push(@ret,@eles);
   }
   $$self{"eles"} = {};
   %{ $$self{"eles"} } = map { $_,1 } @ret;

   @ret = sort(keys %{ $$self{"eles"} });
   $$self{"elesl"} = [@ret];
   $$self{"elesd"} = 1;

   return @ret;
}

# This checks to see if the element is in any source
#
sub ele {
   my($self,$ele) = @_;
   eles($self);

   if (exists $$self{"eles"}{$ele}) {
      return 1;
   }
   return 0;
}

sub eles_in_source {
   my($self,$source) = @_;

   return @{ $$self{"sources"}{$source}{"elesl"} }
     if ($$self{"sources"}{$source}{"elesd"});

   my @ret = ();
   my $data = $$self{"sources"}{$source}{"data"};
   $$self{"sources"}{$source}{"eles"} = {};

   if ($$self{"list"} == 1) {
      for (my $i=0; $i<=$#$data; $i++) {
         $$self{"sources"}{$source}{"eles"}{$i} = 1
           if (defined $$data[$i]  &&
               ! exists $$self{"sources"}{$source}{"default"}{"eles"}{$i});
      }

   } else {
      foreach my $key (keys %$data) {
         $$self{"sources"}{$source}{"eles"}{$key} = 1
           if (! exists $$self{"sources"}{$source}{"default"}{"eles"}{$key});
      }
   }

   @ret = sort(keys %{ $$self{"sources"}{$source}{"eles"} });
   $$self{"sources"}{$source}{"elesl"} = [@ret];
   $$self{"sources"}{$source}{"elesd"} = 1;

   return @ret;
}

sub ele_in_sources {
   my($self,$ele) = @_;

   eles($self);
   my(@ret) = ();

   foreach my $source (keys %{ $$self{"sources"} }) {
      push(@ret,$source)  if (exists $$self{"sources"}{$source}{"eles"}{$ele});
   }
   return @ret;
}

sub ele_in_source {
   my($self,$source,$ele) = @_;

   eles($self);
   return 1  if (exists $$self{"sources"}{$source}{"eles"}{$ele});
   return 0;
}

###############################################################################
# MERGING PEs INTO CEs
###############################################################################

# Construct a CE from one or more PEs.
#
# We'll construct CEs by taking all paths which have a priority list
# associated with them and sorting them shortest to longest. Then,
# we'll take each and construct the full CE starting at that path
# based on the priority list. If there is another path later on which
# is a sub-path of a current path, we'll delete that part of the CE
# and reconstruct it using the new priority list.
#
# Example:
#   If  * is constructed from sources (a,b,c)
#   and /foo is constructed from sources (c,b)
#   then we'll construct the full AE using (a,b,c), then we'll remove the
#   /foo part and reconstruct it using (c,b).
#
sub _construct_ce {
   my($self,$ele) = @_;

   # Test to see if the element exists.

   return  if (! ele($self,$ele));

   # Test to see if the CE has already been created.

   return  if ( ($$self{"list"}  &&  defined($$self{"data"}[$ele]))  ||
                (! $$self{"list"} &&  exists($$self{"data"}{$ele})) );

   # Initialized the main "data" data structure and a new CE.

   $$self{"data"} = _ce_pe_op("empty_ds")  if (! defined $$self{"data"});
   my $ce         = _ce_pe_op($self,"empty_ele");

   # Get the list of all paths which have a priority list and sort them
   # shortest to longest.

   my $obj = $$self{"nds"};

   my @paths = keys %{ $$self{"priority"} };
   @paths    = _sort_paths(@paths);

   # Merge each PE into the CE.

   foreach my $path (@paths) {
      my ($ruleset,@sources) = @{ $$self{"priority"}{$path} };

      # Erase whatever was at the path
      $obj->erase($ce,$path);

      foreach my $source (@sources) {
         next  if (! ele_in_source($self,$source,$ele));

         my($pe) = _ce_pe_op($self,"pe_value",$source,$ele,$path);
         if ($ruleset) {
            $obj->merge_path($ce,$pe,$path,$ruleset);
         } else {
            $obj->merge_path($ce,$pe,$path);
         }
      }
   }

   # Store the CE.

   if ($$self{"list"}) {
      $$self{"data"}[$ele] = $ce;
   } else {
      $$self{"data"}{$ele} = $ce;
   }
}

# Sorts paths by length
#
sub _sort_paths {
   my(@paths) = @_;
   return sort { length($a) <=> length($b) } @paths;
}

# Construct a PE from the data for that element in a given source and
# any defaults in that source.
#
sub _construct_pe {
   my($self,$source,$ele) = @_;

   # Test to see if the element exists in this source.

   return  if (! ele_in_source($self,$source,$ele));

   # Test to see if the PE has already been created.

   return  if ( ($$self{"list"}  &&
                 defined($$self{"sources"}{$source}{"pe"}[$ele]))  ||
                (! $$self{"list"} &&
                 exists($$self{"sources"}{$source}{"pe"}{$ele})) );

   # Initialized the "pe" data structure and a new PE.

   $$self{"sources"}{$source}{"pe"}
     = _ce_pe_op("empty_ds")  if (! defined $$self{"sources"}{$source}{"pe"});
   my $pe = _ce_pe_op($self,"empty_ele");

   # Initialize the new PE to the value in the source.

   my $obj = $$self{"nds"};
   $obj->merge($pe,_ce_pe_op($self,"pe_data",$source,$ele),"replace");

   # Get the list of default elements to merge in.

   my @def = @{ $$self{"sources"}{$source}{"default"}{"order"} };

   # Merge each default into the PE.

 DEF: foreach my $def (@def) {
      my($defele,@args) = @$def;
      $defele = $$self{"sources"}{$source}{"default"}{"eles"}{$defele};

      # Test to see if @args contains a ruleset as the first entry.

      my $ruleset = "default";
      if (@args) {
         if ($obj->ruleset_valid($args[0])) {
            $ruleset = shift(@args);
         }
      }

      # Next test to see if @args contains a path.

      my $path = "";
      my $val;

      if (@args) {
         $path = shift(@args);
         my $valid;
         ($valid,$val) = $obj->valid($pe,$path);
         next DEF  if (! $valid);
      }

      # Finally, test to see if @args contains a value

      if (@args) {
         next  if ($val ne $args[0]);
      }

      # This default applies to this PE, so merge it in.

      $obj->merge($pe,$defele,$ruleset);
   }

   # Store the PE.

   if ($$self{"list"}) {
      $$self{"sources"}{$source}{"pe"}[$ele] = $pe;
   } else {
      $$self{"sources"}{$source}{"pe"}{$ele} = $pe;
   }
}

# This returns a value for a CE or PE based on the operation.
#
#    empty_ele      : Returns [] or {} depending on the type of elements
#    empty_ds       : Returns [] or {} depending on the type of data structure
#    pe_data SOURCE ELE
#                   : Returns the raw PE from a source
#    pe_value SOURCE ELE PATH
#                   : Returns the PE (with defaults) value at the given path
#    ce_data ELE    : Returns the CE
#    ce_value ELE PATH
#                   : Returns the CE value at the given path
#
sub _ce_pe_op {
   my($self,$op,@args) = @_;
   my $obj = $$self{"nds"};

   if ($op eq "empty_ele") {
      if ($obj->get_structure("/","type") eq "array") {
         return [];
      } else {
         return {};
      }

   } elsif ($op eq "empty_ds") {
      if ($$self{"list"}) {
         return [];
      } else {
         return {};
      }

   } elsif ($op eq "pe_data") {
      my($source,$ele) = @args;

      if ($$self{"list"}) {
         return $$self{"sources"}{$source}{"data"}[$ele];
      } else {
         return $$self{"sources"}{$source}{"data"}{$ele};
      }

   } elsif ($op eq "pe_value") {
      my($source,$ele,$path) = @args;
      _construct_pe($self,$source,$ele);

      if ($$self{"list"}) {
         return $obj->value($$self{"sources"}{$source}{"pe"}[$ele],$path);
      } else {
         return $obj->value($$self{"sources"}{$source}{"pe"}{$ele},$path);
      }

   } elsif ($op eq "ce_data") {
      my($ele) = @args;
      _construct_ce($self,$ele);

      if ($obj->get_structure("/","type") eq "array") {
         return $$self{"data"}[$ele];
      } else {
         return $$self{"data"}{$ele};
      }

   } elsif ($op eq "ce_value") {
      my($ele,$path) = @args;
      _construct_ce($self,$ele);

      if ($$self{"list"}) {
         return $obj->value($$self{"data"}[$ele],$path);
      } else {
         return $obj->value($$self{"data"}{$ele},$path);
      }

   }
}

###############################################################################
# ACCESS METHOD
###############################################################################

sub access {
   my($self,$ele,$path,$warnings) = @_;
   my $array  = wantarray;
   my $obj    = $$self{"nds"};

   #
   # Get the list of elements being done, and do simple checks.
   #

   my @ele;
   my $elelist = 0;
   if (ref($ele)) {
      @ele     = @$ele;
      $elelist = 1;
   } else {
      @ele     = ($ele);
   }

   #
   # Check for a valid path in each ele
   #

   my @tmp;
   foreach my $e (@ele) {
      if (! ele($self,$e)) {
         _Error("[access] Invalid element",0,$e,0,0,0);
         next;
      }
      my $val = _ce_pe_op($self,"ce_value",$e,$path);
      if (! defined $val) {
         _Error("[access] Path not defined in element",0,$e,0,0,0)
           if ($warnings);
         next;
      }
      push(@tmp,$e);
   }
   @ele = @tmp;

   if (! @ele) {
      _Error("[access] Empty element list",0,0,0,0,0)  if ($warnings);
      return undef;
   }

   #
   # Find the structure that exists at the path
   #

   my $struct = $obj->get_structure($path,"type");

   #
   # Scalar context, single element
   #
   #    Path     Returns
   #    -----    --------------
   #    scalar   The value at path
   #    list     The length of the list
   #    hash     undef
   #

   if (! $array  &&  ! $elelist) {
      if ($struct eq "scalar") {
         my $val = _ce_pe_op($self,"ce_value",$ele,$path);
         return $val;

      } elsif ($struct eq "array") {
         my $val = _ce_pe_op($self,"ce_value",$ele,$path);
         return $#$val + 1;

      } elsif ($struct eq "hash") {
         return undef;
      }
   }

   #
   # List context, single name
   #
   #    Path     Returns
   #    -----    --------------
   #    scalar   undef
   #    list     The list of elements
   #    hash     The list of hash keys
   #

   if ($array  &&  ! $elelist) {
      if ($struct eq "scalar") {
         return undef;

      } elsif ($struct eq "array") {
         my $val = _ce_pe_op($self,"ce_value",$ele,$path);
         return @$val;

      } elsif ($struct eq "hash") {
         my $val = _ce_pe_op($self,"ce_value",$ele,$path);
         return sort(keys %$val);
      }
   }

   #
   # List context, list of names
   #
   #    Path     Returns
   #    -----    --------------
   #    scalar   A hash of ele => value
   #    list     A hash of ele => listref
   #    hash     A hash of ele => hashref
   #

   if ($array  &&  $elelist) {
      my %ret = ();
      foreach my $e (@ele) {
         my $val = _ce_pe_op($self,"ce_value",$e,$path);
         $ret{$e} = $val;
      }
      return %ret;
   }

   #
   # Scalar context, list of names
   #
   #    Path     Returns
   #    -----    --------------
   #    scalar   undef
   #    list     undef
   #    hash     undef
   #

   return undef;
}

###############################################################################
# WHICH METHOD
###############################################################################

sub which {
   my($self,@args) = @_;
   my $obj = $$self{"nds"};
   my @ret = eles($self);

 MATCH: while (@args) {
      my $path = shift(@args);
      my $val  = shift(@args);
      my @ele  = @ret;
      @ret     = ();

      #
      # $path must be valid.
      #

      my $struct = $obj->get_structure($path,"type");
      if (! $struct) {
         _Error("[which] Invalid path",0,$path,0,0,0);
         next MATCH;
      }

      #
      # If $path points to a scalar, return a list of names where
      # the scalar is set to $val.
      #

      if ($struct eq "scalar") {
         foreach my $ele (@ele) {
            my $v = _ce_pe_op($self,"ce_value",$ele,$path);
            next  if (! defined $v);

            if      ($val eq "_defined_") {

            } elsif ($val eq "_nonzero_") {
               next  if ($v == 0);

            } elsif ($val eq "_true_") {
               next  if (! $v);

            } elsif ($val eq "_false_") {
               next  if ($v)

            } else {
               next  if ($v ne $val);
            }
            push(@ret,$ele);
         }
      }

      #
      # Lists
      #

      if ($struct eq "array") {

         #
         # Special values
         #

         my($min,$max,$test,$childstruct);
         if ($val eq "_empty_") {
            $test = "empty";
         } elsif ($val eq "_nonempty_") {
            $min  = 1;
            $test = "min";
         } elsif ($val =~ /^_(\d+)_$/) {
            $min  = $1;
            $test = "defined";
         } elsif ($val =~ /^_=(\d+)_$/) {
            ($min,$max) = ($1,$1);
            $test = "range";
         } elsif ($val =~ /^_>(\d+)_$/) {
            $min  = $1;
            $test = "min";
         } elsif ($val =~ /^_<(\d+)_$/) {
            ($min,$max) = (0,$1-1);
            $test = "range";

         } else {
            $childstruct = $obj->get_structure("$path/0","type");
            if ($childstruct ne "scalar") {
               $min  = $val;
               $test = "defined";
            }
         }

         if ($test) {
            foreach my $ele (@ele) {
               my $vals = _ce_pe_op($self,"ce_value",$ele,$path);
               if (! defined $vals) {
                  push(@ret,$ele)  if ($test eq "empty");
                  next;
               }
               my $n    = $#$vals + 1;
               next  if (($test eq "empty")  ||
                         ($test eq "min"  &&  $n < $min)  ||
                         ($test eq "range"  &&  ($n < $min  || $n > $max))  ||
                         ($test eq "defined"  &&  ! defined $$vals[$min]));
               push(@ret,$ele);
            }
            next MATCH;

         } else {

            #
            # If $path points to a list of scalars, all elements which contain
            # $val in the list.
            #

          N1: foreach my $ele (@ele) {
               my $vals = _ce_pe_op($self,"ce_value",$ele,$path);
               next  if (! defined $vals);
               foreach my $v (@$vals) {
                  if ($v eq $val) {
                     push(@ret,$ele);
                     next N1;
                  }
               }
            }
         }
      }

      #
      # If $path points to a hash, all elements are returned which have
      # $val as a hash key (it must exist AND point to a defined
      # value).
      #

      if ($struct eq "hash") {
         foreach my $ele (@ele) {
            my $v = _ce_pe_op($self,"ce_value",$ele,"$path/$val");
            next  if (! defined $v);
            push(@ret,$ele);
         }
      }
   }

   return sort @ret;
}

###############################################################################
# WHICH_SOURCE METHOD
###############################################################################

sub which_sources {
   my($self,$ele,$path,$flag) = @_;
   $flag          = "all"  if (! $flag);
   return (0,1)   if (! $self->ele($ele));
   my $obj        = $$self{"nds"};
   my $type       = $obj->get_structure($path,"type");
   return (0,2)   if ($type eq "unknown"  ||  ! $type);
   return (0,3)   if ($type ne "scalar"  &&
                      ($flag eq "all-val"  ||
                       $flag eq "readonly-val"  ||
                       $flag eq "writable-val"));

   _construct_ce($self,$ele);
   my $val        = _ce_pe_op($self,"ce_value",$ele,$path);
   return (0,-1)  if (! defined $val  ||  $val eq "");

   my @sources    = sources($self);
   my @ret;
   foreach my $source (@sources) {
      my $v       = _ce_pe_op($self,"pe_value",$source,$ele,$path);
      next        if (! defined $v  ||  $v eq "");

      if      ($flag eq "all") {

      } elsif ($flag eq "all-val") {
         next  if ($v ne $val);

      } elsif ($flag eq "readonly") {
         next  if ($$self{"sources"}{$source}{"writable"});

      } elsif ($flag eq "readonly-val") {
         next  if ($v ne $val);
         next  if ($$self{"sources"}{$source}{"writable"});

      } elsif ($flag eq "writable") {
         next  if (! $$self{"sources"}{$source}{"writable"});

      } elsif ($flag eq "writable-val") {
         next  if ($v ne $val);
         next  if (! $$self{"sources"}{$source}{"writable"});

      } else {
         _Error("[which_sources] Invalid flag",1,$flag,0,0,1);
      }

      push(@ret,$source);
   }
   if (@ret) {
      return (1,@ret);
   } else {
      return (0,0);
   }
}

###############################################################################
# DELETE_ELE METHOD
###############################################################################

sub delete_ele {
   my($self,$ele) = @_;

   #
   # We need to handle hashes, ordered lists, and unordered lists
   # separately.
   #

   my($list,$ordered);
   $list = $$self{"list"};
   if ($list) {
      my $nds = $$self{"nds"};
      $ordered = $nds->get_structure("/","ordered");
   }

   #
   # Delete the raw data element from each source, the partial
   # element, and then force the source element list to be updated.
   #

   my @sources    = sources($self);
   foreach my $source (@sources) {
      if      ($list  &&  $ordered) {
         # Top level ordered list - set the element to undef, but
         # it's not necessary to update element lists
         if (defined $$self{"sources"}{$source}{"data"}[$ele]) {
            $$self{"sources"}{$source}{"data"}[$ele] = undef;
            $$self{"sources"}{$source}{"modified"}   = 1;
         }
         if (defined $$self{"sources"}{$source}{"pe"}[$ele]) {
            $$self{"sources"}{$source}{"pe"}[$ele]   = undef;
         }

      } elsif ($list) {
         # Top level unordered list
         if (defined $$self{"sources"}{$source}{"data"}[$ele]) {
            splice( @{ $$self{"sources"}{$source}{"data"} },$ele,1 );
            $$self{"sources"}{$source}{"modified"} = 1;
            $$self{"sources"}{$source}{"elesd"}    = 0;
         }
         if (defined $$self{"sources"}{$source}{"pe"}[$ele]) {
            splice( @{ $$self{"sources"}{$source}{"pe"} },$ele,1 );
         }

      } else {
         # Top level hash
         if (exists $$self{"sources"}{$source}{"data"}{$ele}) {
            delete $$self{"sources"}{$source}{"data"}{$ele};
            delete $$self{"sources"}{$source}{"pe"}{$ele};
            $$self{"sources"}{$source}{"modified"} = 1;
            $$self{"sources"}{$source}{"elesd"}    = 0;
         }
      }
   }

   #
   # Now delete the combined element and force the element list
   # to be updated.
   #

   if      ($list  &&  $ordered) {
      # Top level ordered list - set the element to undef, but
      # it's not necessary to update element lists
      if (defined $$self{"data"}[$ele]) {
         $$self{"data"}[$ele] = undef;
      }

   } elsif ($list) {
      # Top level unordered list
      if (defined $$self{"data"}[$ele]) {
         splice( @{ $$self{"data"} },$ele,1 );
      }
      $$self{"elesd"} = 0;

   } else {
      if (exists $$self{"data"}{$ele}) {
         delete $$self{"data"}{$ele};
      }
      $$self{"elesd"} = 0;
   }
}

###############################################################################
# RENAME_ELE METHOD
###############################################################################

sub rename_ele {
   my($self,$ele,$newele) = @_;

   #
   # Check to make sure that $newele is available.
   #

   return 1  if (ele($self,$newele));

   #
   # Rename the raw data element from each source, the partial
   # element, and then force the source element list to be updated.
   #

   my @sources    = sources($self);
   foreach my $source (@sources) {
      if (exists $$self{"sources"}{$source}{"data"}{$ele}) {
         $$self{"sources"}{$source}{"data"}{$newele} =
           $$self{"sources"}{$source}{"data"}{$ele};
         delete $$self{"sources"}{$source}{"data"}{$ele};

         if (exists $$self{"sources"}{$source}{"pe"}{$ele}) {
            $$self{"sources"}{$source}{"pe"}{$newele} =
              $$self{"sources"}{$source}{"pe"}{$ele};
            delete $$self{"sources"}{$source}{"pe"}{$ele};
         }

         $$self{"sources"}{$source}{"modified"} = 1;
         $$self{"sources"}{$source}{"elesd"}    = 0;
      }
   }

   #
   # Now delete the combined element and force the element list
   # to be updated.
   #

   if (exists $$self{"data"}{$ele}) {
      $$self{"data"}{$newele} = $$self{"data"}{$ele};
      delete $$self{"data"}{$ele};
   }
   $$self{"elesd"} = 0;

   return 0;
}

###############################################################################
# UPDATE_ELE METHOD
###############################################################################

sub update_ele {
   my($self,$ele,$path,$val,@args) = @_;
   my $nds = $$self{"nds"};

   #
   # Determine $which, $ruleset
   #

   my($which,$ruleset);
   if      ($#args == -1) {
      $ruleset = "replace";

   } elsif ($#args == 0) {
      if ($args[0] eq ""  ||
          $nds->ruleset_valid($args[0])) {
         $ruleset = $args[0];
      } else {
         $which   = $args[0];
         $ruleset = "replace";
      }

   } elsif ($#args == 1) {
      ($which,$ruleset) = @args;

   } else {
      _Error("[update_ele] Invalid options",0,join(" ",@args),0,0,0);
      return 1;
   }

   #
   # Check options.
   #

   $which = "currval"  if (! $which);
   my $whichsource = "";
   if ($which =~ /^>(\S+)$/) {
      $whichsource = $1;
      my %tmp = map { $_,1 } $self->sources;
      if (! exists $tmp{$whichsource}) {
         _Error("[update_ele] Invalid source",0,$which,0,0,0);
         return 2;
      }

   } elsif ($which ne "curr"  &&  $which ne "currval"  &&
            $which ne "all") {
      _Error("[update_ele] Invalid option",0,$which,0,0,0);
      return 1;
   }

   if (ref($val)) {
      $which = "curr"   if ($which eq "currval");
      $which = "first"  if ($which eq "firstval");
   }

   #
   # Check the structure of $val. It's okay to add new structure here.
   #

   if (defined $val) {
      my($err,$v) = $nds->check_value($path,$val,1);
      if ($err) {
         _Error("[update_ele] Invalid structure",0,$err,$val,0,0);
         return 3;
      }
   }

   #
   # Determine which sources to update
   #

   my @source;
   if      ($whichsource) {
      @source = ($whichsource);

   } elsif ($which eq "curr") {
      @source = which_sources($self,$ele,$path,"writable");

   } elsif ($which eq "currval") {
      @source = which_sources($self,$ele,$path,"writable-val");

   } elsif ($which eq "all") {
      my @sources    = sources($self);
      foreach my $source (@sources) {
         push(@source,$source)  if ($$self{"sources"}{$source}{"writable"});
      }
   }

   #
   # Remove sources which do not contain the element
   #

   my %tmp = map { $_,1 } ele_in_sources($self,$ele);
   my @tmp;
   foreach my $source (@source) {
      push(@tmp,$source)  if (exists $tmp{$source});
   }
   @source = @tmp;

   #
   # Update the sources.
   #

   return 4  if (! @source);
   foreach my $source (@source) {
      my $err = _update_ele($self,$ele,$path,$val,$source,$ruleset);
      if ($err) {
         _Error("[update_ele] Update failed",0,$err,$source,0,0);
         return 5;
      }
   }

   #
   # Delete the CE (it'll be recreated if used)
   #

   if ($$self{"list"}) {
      if (defined $$self{"data"}[$ele]) {
         $$self{"data"}[$ele] = undef;
      }
   } else {
      if (exists $$self{"data"}{$ele}) {
         delete $$self{"data"}{$ele};
      }
   }

   return 0;
}

sub _update_ele {
   my($self,$ele,$path,$val,$source,$ruleset) = @_;
   my $nds = $$self{"nds"};
   my $err;

   if (! defined $val) {

      #
      # If $val is undefined, erase the path
      #

      if ($$self{"list"}) {
         $err = $nds->erase($$self{"sources"}{$source}{"data"}[$ele],$path);
      } else {
         $err = $nds->erase($$self{"sources"}{$source}{"data"}{$ele},$path);
      }

   } else {

      #
      # Update this source
      #

      if ($$self{"list"}) {
         $err = $nds->merge_path($$self{"sources"}{$source}{"data"}[$ele],
                                 $val,$path,$ruleset);
      } else {
         $err = $nds->merge_path($$self{"sources"}{$source}{"data"}{$ele},
                                 $val,$path,$ruleset);
      }
   }

   return $err  if ($err);

   $$self{"sources"}{$source}{"modified"} = 1;

   #
   # Remove the PE (it'll be regenerated as needed)
   #

   if ($$self{"list"}) {
      $$self{"sources"}{$source}{"pe"}[$ele] = undef
        if (defined $$self{"sources"}{$source}{"pe"}[$ele]);

   } else {
      delete $$self{"sources"}{$source}{"pe"}{$ele}
        if (exists $$self{"sources"}{$source}{"pe"}{$ele});
   }

   return 0;
}

###############################################################################
# PATH_SOURCES METHOD
###############################################################################

sub path_sources {
   my($self,$path) = @_;
   my(@sources);

   my @paths = _sort_paths(keys %{ $$self{"priority"} });
   my $ruleset;
   foreach my $p (@paths) {
      if ($path eq $p  ||
          $p eq "/"    ||
          $path =~ /^\Q$p\E\//) {
         ($ruleset,@sources) = @{ $$self{"priority"}{$p} };
      }
   }
   return @sources;
}

###############################################################################
# ADD METHOD
###############################################################################

sub add {
   my($self,$ele,$val) = @_;

   if (ele($self,$ele)) {
      _Error("[add] Element already exists",0,$ele,0,0,0);
      return 1;
   }

   #
   # Check the structure
   #

   my $nds = $$self{"nds"};
   my($err,$v) = $nds->check_structure($val,1);
   return 2  if ($err);

   #
   # Get the list of writable sources
   #   $writable{SOURCE} => 1
   #

   my %writable;
   foreach my $source (sources($self)) {
      $writable{$source} = 1  if ($$self{"sources"}{$source}{"writable"});
   }

   #
   # Get the first writable source for each path.
   #   $path{PATH} => SOURCE
   #   @paths = (PATH1 PATH2 ... PATHn)   (ordered shortest to longest)
   #

   my %path;
   my @paths = keys %{ $$self{"priority"} };

   foreach my $p (@paths) {
      my($ruleset,@sources) = @{ $$self{"priority"}{$p} };
      foreach my $s (@sources) {
         next  if (! exists $writable{$s});
         $path{$p} = $s;
         last;
      }
   }
   @paths = _sort_paths(keys %path);

   #
   # $src{$source} will point to the part of the structure that
   # belongs to that source
   #

   my %src;
   while (@paths) {
      #
      # Start at the deepest level in $val and see if there is
      # the new element contains that path
      #
      # Merge it in, starting with the deepest.
      my $p = pop(@paths);
      my($valid,$v) = $nds->valid($val,$p,1);
      next  if (! $valid);
      #
      # Remove that path from the new element and merge it into
      # the appropriate %src element.
      #
      $nds->erase($val,$p);
      my $s = $path{$p};
      if (! exists $src{$s}) {
         if (ref($val) eq "HASH") {
            $src{$s} = {};
         } else {
            $src{$s} = [];
         }
      }
      $nds->merge_path($src{$s},$v,$p);
      $val = undef  if ($p eq "/");
   }

   #
   # At this point, we should have completely partitioned up the
   # new element.
   #

   if (defined $val) {
      _Error("[add] Element contains data that could not be assigned",
             0,$ele,0,0,0);
      return 3;
   }

   #
   # Now, transfer this partitioned value to the raw data for each
   # source.
   #

   foreach my $s (keys %src) {
      if ($$self{"list"}) {
         $$self{"sources"}{$s}{"data"}[$ele] = $src{$s};
      } else {
         $$self{"sources"}{$s}{"data"}{$ele} = $src{$s};
      }
      $$self{"sources"}{$s}{"modified"} = 1;
      $$self{"sources"}{$s}{"elesd"}    = 0;
   }
   $$self{"elesd"} = 0;

   return 0;
}

###############################################################################
# DUMP METHOD
###############################################################################

sub dump {
   my($self,$ele,$path,%opts) = @_;
   $path = "/"  if (! $path);

   my $nds = $$self{"nds"};
   return $nds->print(_ce_pe_op($self,"ce_value",$ele,$path),%opts);
}

###############################################################################
# SAVE METHOD
###############################################################################

sub save {
   my($self,$nobackup) = @_;

   my @source = sources($self);
   foreach my $source (@source) {
      next  if (! $$self{"sources"}{$source}{"modified"});

      my $type = $$self{"sources"}{$source}{"type"};
      if ($type eq "yaml") {
         _save_yaml($self,$source,$nobackup);
      } else {
         _Error("[save] Invalid source type",1,$source,$type,0,1);
      }

      $$self{"sources"}{$source}{"modified"} = 0;
   }
}

sub _save_yaml {
   my($self,$source,$nobackup) = @_;
   my $file = $$self{"sources"}{$source}{"file"};

   # Backup file

   if (! $nobackup) {
      rename $file,"$file.bak"  ||
        _Error("[save_yaml] Unable to backup file",1,$file,0,0,1);
   }

   # Write data

   my $out = new IO::File;
   $out->open(">$file") ||
     _Error("[save_yaml] Unable to write file",1,$file,$!,0,1);
   print $out Dump($$self{"sources"}{$source}{"data"});
   $out->close();
}

###############################################################################
# MY LIBRARY ROUTINES
###############################################################################

# $err      : the error message
# $severe   : 0 (warning) or 1 (error)
# $category : added to the error message (SEVERITY: MSG: CAT [SUBCAT]: WHY)
# $subcat
# $why
# $act      : \$var   =>   $var=$err
#             \@err   =>   push(@err,$err)
#             \&func  =>   &func($err)
#             \OUT    =>   print OUT $err
#             "ret"   =>   return $err
#             1       =>   die $err
#             0       =>   print $err
#
sub _Error {
   my($err,$severe,$category,$subcat,$why,$act)=@_;

   $err = ($severe ? "ERROR: $err" : "WARNING: $err");

   if (defined $category  &&  $category  &&  defined $subcat  &&  $subcat) {
      $err="$err: $category [ $subcat ]";
   } elsif (defined $category  &&  $category) {
      $err="$err: $category";
   }

   if (defined $why  &&  $why) {
      $err="$err: $why";
   }

   # Perform the action

   if (ref($act)) {
      if (ref($act) eq "SCALAR") {
         $$act=$err;

      } elsif (ref($act) eq "ARRAY") {
         push @$act,$err;

      } elsif (ref($act) eq "CODE") {
         &$act($err);

      } else {
         print $act "$err\n";

      }

   } elsif ($act eq "ret") {
      return $err;

   } elsif ($act) {
      confess "$err\n";

   } else {
      print "$err\n";
   }
}

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
