package Finance::Platform::Wrapper::Role::IG;

# ABSTRACT :
use Moo::Role;
our $VERSION = 'v1.0.5';
##~ DIGEST : 01668a3abd4e103e5c487b698cbf3908
with qw/
  Moo::Role::JSON
  /;
DEPENDENCIES: {
	use JSON;         #need constants from this
	use Data::Dumper; #audit writing
}
ACCESSORS: {
	OPERATION: {
		has rooturl       => ( is => 'rw', );
		has accountstatus => ( is => 'rw' );
		has currency      => ( is => 'ro', default => sub { 'GBP' } ); # should never change
	}
	AUTH: {
		has key              => ( is => 'rw', );
		has cst              => ( is => 'rw', );
		has cstage           => ( is => 'rw', );
		has securitytoken    => ( is => 'rw', );
		has securitytokenage => ( is => 'rw', );
	}
}

=head1 CODE
=head2 PRIMARY
	The heavy lifting
=head3 auditedrequest
	IG is quite strict on auditing all requests - so this makes working directories and fills them with the req and res objects
=cut

sub auditedrequest {
	my ( $self, $p, $q, $headers, ) = @_;
	$q ||= {};

	#this *might* be persistable
	my $ua = $self->lwpuseragent();
	$ua->timeout( $self->defaulttimeout );

	#build the request
	require HTTP::Request;
	my $req = HTTP::Request->new( $p->{type}, $p->{url} );

	#cargo cultin'
	$req->header(
		'Version'      => $p->{version} || 2,
		'X-IG-API-KEY' => $self->key(),
		'Content-Type' => 'application/json; charset=UTF-8',
		'Accept'       => 'application/json; charset=UTF-8',
	);
	for my $header ( keys( %{$headers} ) ) {
		$req->header( $header => $headers->{$header} );
	}
	if ( %{$q} ) {
		$req->content( $self->json->encode( $q ) );
	}

	#log what we're about to do
	LOGREQ: {
		my ( $s, $usec ) = $self->gettimeofday();
		my $requestfh = $self->ofh( $self->auditdir() . "/$s\_$usec\_request.pm" );
		print $requestfh Dumper( $req );
		close( $requestfh );
	}

	#hcf when/where necessary
	my $result;
	LOGRESPONSE: {
		my ( $s, $usec ) = $self->gettimeofday();
		my $responsefh = $self->ofh( $self->auditdir() . "/$s\_$usec\_response.pm" );
		$result = $ua->request( $req );
		print $responsefh Dumper( $result );
		close( $responsefh );
	}
	if ( $result->{_rc} != 200 ) {
		if ( $result->{_content} ) {
			$self->log( $result->{_content} );
		}
		$self->log( "Request failed - check audit for cause" );
		exit;
	}
	return ( $result );
}

sub login {
	my ( $self ) = @_;
	$self->log( "Starting new session" );

	# 	my $key = $self->getencryptionkey();
	# 	$self->pass($self->encrypt($self->pass()));
	my $res = $self->auditedrequest(
		{
			url  => $self->rooturl() . '/session',
			type => 'POST'
		},
		{
			identifier        => $self->user(),
			encryptedPassword => JSON::false,
			password          => $self->pass(),
		}
	);
	$self->accountstatus( $self->json->decode( $res->{_content} ) );
	$self->securitytoken( $res->{_headers}->{'x-security-token'} );
	$self->log( "Got security token value [$res->{_headers}->{'x-security-token'}]" );
	$self->cst( $res->{_headers}->{cst} );
	$self->log( "Got cst value [$res->{_headers}->{cst}]" );
	my $now = time;
	$self->cstage( $now );
	$self->securitytokenage( $now );
}

=head3 getepic
	get the IG trading platform unique value for a $something
=cut

sub getepics {
	my ( $self, $search ) = @_;
	my $res = $self->auditedrequest(
		{
			url     => $self->rooturl() . "/markets?searchTerm=$search",
			type    => 'GET',
			version => 1,
		},
		undef,
		$self->authheaders()
	);
	print Dumper( $res );
}

sub getepicdetail {
	my ( $self, $epiccode ) = @_;
	my $res = $self->auditedrequest(
		{
			url     => $self->rooturl() . "/markets/$epiccode",
			type    => 'GET',
			version => 1,
		},
		undef,
		$self->authheaders()
	);
	print Dumper( $res );
}

sub order {
	my ( $self, $p ) = @_;

	#default-able
	my $orderbody = {
		currencyCode  => $p->{currency}      || $self->currency(),
		dealReference => $p->{dealReference} || $self->snakeuuid(),
		timeInForce => ( $p->{timeInForce} ? $p->{timeInForce} : 'GOOD_TILL_CANCELLED' ),
		type        => ( $p->{type} && $p->{type} eq 'STOP' ) ? 'STOP' : 'LIMIT'
	};
	REQUIRED: {
		for my $required (
			qw/
			direction
			epic
			size
			level
			expiry
			/
		  )
		{
			confess( "$required not provided" ) unless $p->{$required};
		}
		$orderbody->{direction} = uc( $p->{direction} );

		#always uppercase - IG's proprietary identifiers
		$orderbody->{epic} = $p->{epic};

		#how big an order
		$orderbody->{size} = $p->{size};

		#when to carry out the order (?)
		$orderbody->{level} = $p->{level};

		#when expires - not sure why this is here
		$orderbody->{expiry} = $p->{expiry};

		#when expires - not sure why this is here
	}

	#BOOLEAN
	for (
		qw/
		forceOpen
		guaranteedStop
		/
	  )
	{
		$orderbody->{$_} = $p->{$_} ? JSON::true : JSON::false;
	}

	#optional - but stopDistance is required ;\
	for (
		qw/
		goodTillDate
		limitDistance
		stopDistance
		stopLevel
		limitLevel
		/
	  )
	{
		$orderbody->{$_} = $p->{$_};
	}
	DUMPSTRUCTURE: {
		$self->log( "Creating order structure dump" );
		my ( $s, $usec ) = $self->gettimeofday();
		my $ofh = $self->ofh( $self->auditdir() . "/$s\_$usec\_order_structure.pm" );
		print $ofh Dumper( $orderbody );
		close( $ofh );
	}
	$self->auditedrequest(
		{
			url  => $self->rooturl() . '/workingorders/otc',
			type => 'POST',
		},
		$orderbody,
		$self->authheaders()
	);
}

sub listorders {
	my ( $self ) = @_;
	$self->auditedrequest(
		{
			url  => $self->rooturl() . '/workingorders',
			type => 'GET',
		},
		undef,
		$self->authheaders()
	);
}

sub gethistory {
	my ( $self, $from, $to ) = @_;
	my $res = $self->auditedrequest(
		{
			url     => $self->rooturl() . "/history/activity/$from/$to",
			type    => 'GET',
			version => 1,
		},
		undef,
		$self->authheaders()
	);
	return $self->json->decode( $res->{_content} );

}

sub gettransactions {
	my ( $self, $from, $to ) = @_;
	my $res = $self->auditedrequest(
		{
			url  => $self->rooturl() . "/history/transactions",
			type => 'GET',
		},
		{
			# 			from => $from,
			# 			to => $to,
		},
		$self->authheaders()
	);
	return $self->json->decode( $res->{_content} );

}

sub writecsv {
	my ( $self, $data, $target ) = @_;
	use Toolbox::FileIO::CSV;
	my $csv = Toolbox::FileIO::CSV::getcsv;
	my $colorder;

	open( my $ofh, '>:utf8', $target );
	for my $transaction ( @{$data} ) {
		unless ( $colorder ) {
			$colorder = [ sort( keys( %{$transaction} ) ) ];
			$csv->print( $ofh, $colorder );
		}
		$csv->print( $ofh, [ @{$transaction}{@{$colorder}} ] );
	}
	close( $ofh );

}

=head2 SECONDARY
	the refactored methods used in PRIMARY subs
=head3 getencryptionkey
	used to mask the password apparently
=cut

sub getencryptionkey {
	my ( $self ) = @_;
	my $res = $self->auditedrequest(
		{
			url  => $self->rooturl() . '/session/encryptionKey',
			type => 'GET'
		}
	);
	my $decodedres = $self->json->decode( $res->{_content} );
	die Dumper( $decodedres );
}

# TODO actually do something
sub encrypt {
	my ( $self, $pass ) = @_;
	return '';
}

=head3 authheaders
	return the current correct auth headers or HCF
=cut

sub authheaders {
	my ( $self ) = @_;
	my $maxold = ( time - 57 );
	if ( $self->cstage() <= $maxold ) {
		$self->logexit( 'CST is too old' );
	}
	if ( $self->securitytokenage() <= $maxold ) {
		$self->logexit( 'Security token is too old' );
	}
	return {
		'x-security-token' => $self->securitytoken(),
		cst                => $self->cst()
	};
}

=head1 AUTHOR
	mmacnair, C<< <mmacnair at cpan.org> >>
=head1 BUGS
	TODO Bugs
=head1 SUPPORT
	TODO Support
=head1 ACKNOWLEDGEMENTS
	TODO
=head1 COPYRIGHT
	Copyright 2020 mmacnair.
=head1 LICENSE
	Copyright 2020 M.Macnair
	Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:
	1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
	2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
	3. Neither the name of the copyright holder nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.
	THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
=cut

1;
