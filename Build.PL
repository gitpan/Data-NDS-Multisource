
use Module::Build;

my $build = Module::Build->new(
	license            => 'perl',
	dist_version       => '2.01',
	dist_author        => 'Sullivan Beck <sbeck@cpan.org>',
	module_name        => 'Data::NDS::Multisource',
	dist_abstract      => 'Data structures defined in multiple sources',
	requires           => {
		'perl'                => '5.6.0',
		'Carp'                => '0',
		'Cwd'                 => '0',
		'Data::NDS'           => '0',
		'File::Basename'      => '0',
		'File::Spec'          => '0',
		'YAML::Syck'          => '0',
	},
	build_requires     => {
		'File::Copy'          => '0',
		'Test::More'          => '0',
	},
	build_recommends   => {
		'Test::Pod'           => '0',
		'Test::Pod::Coverage' => '0',
	},
	sign               => 1,
);

$build->create_build_script;
