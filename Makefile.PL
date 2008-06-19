
use ExtUtils::MakeMaker;

WriteMakefile(
	NAME             => 'Data::NDS::Multisource',
	VERSION	         => '2.02',
	($] >= 5.005
	? (ABSTRACT=>'Data structures defined in multiple sources',
	   AUTHOR  =>'Sullivan Beck (sbeck@cpan.org)')
	: ()),
	'dist' => {COMPRESS=>'gzip',SUFFIX=>'gz'},
        PL_FILES  => {},
	PREREQ_PM => {
		'Carp'                => '0',
		'Cwd'                 => '0',
		'Data::NDS'           => '0',
		'File::Basename'      => '0',
		'File::Spec'          => '0',
		'YAML::Syck'          => '0',
		'File::Copy'          => '0',
		'Test::More'          => '0',
		'Test::Pod'           => '0',
		'Test::Pod::Coverage' => '0',
	},
);
