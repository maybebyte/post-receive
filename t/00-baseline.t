#!/usr/bin/env perl
use strict;
use warnings;

use English qw(-no_match_vars);
use File::Basename qw(dirname);
use File::Spec;
use Test::More;

my $test_dir = dirname( File::Spec->rel2abs(__FILE__) );
my $hook = File::Spec->canonpath( File::Spec->catfile(
	$test_dir, File::Spec->updir, 'bin', 'post-receive'
) );

ok( -e $hook, 'hook exists' );
ok( -f $hook, 'hook is a regular file' );
ok( -x $hook, 'hook is executable' );

my $syntax_status = system {$EXECUTABLE_NAME} $EXECUTABLE_NAME, '-c', $hook;
is( $syntax_status, 0, 'perl -c succeeds' );

done_testing();
