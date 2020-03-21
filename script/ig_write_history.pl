#!/usr/bin/perl
use strict;
use warnings;
use Toolbox::CombinedCLI;
use Finance::Platform::Wrapper::Class::IG;
main();

sub main {
	my $conf = Toolbox::CombinedCLI::get_config(
		[
			qw/
			  user
			  pass
			  rooturl
			  key
			  auditroot

			  path
			  /
		],
	);
	my $ig   = Finance::Platform::Wrapper::Class::IG->new( $conf );
	my $data = $ig->jsonloadfile( $conf->{path} );
	$ig->writehistory( $data, "./tmp.csv" );

}
