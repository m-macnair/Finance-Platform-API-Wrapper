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

			  /
		],
	);
	my $ig = Finance::Platform::Wrapper::Class::IG->new( $conf );
	$ig->login();
	my $result = $ig->gettransactions( '19-03-2020', '20-03-2020' );
	$ig->writecsv( $result->{transactions}, "./transactions.csv" );

	$ig->log( 'finished' );

}
