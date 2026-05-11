package PostReceive::TestHarness;

use strict;
use warnings;

use File::Basename qw(dirname);
use File::Spec;

require File::Spec->catfile(
	dirname(__FILE__),
	File::Spec->updir,
	File::Spec->updir,
	File::Spec->updir,
	'lib',
	'PostReceive',
	'TestHarness.pm',
);

1;
