package Finance::Platform::Wrapper::Role::Shared;

# ABSTRACT :
use Moo::Role;

our $VERSION = 'v1.0.4';
##~ DIGEST : e6f50db1ce0177f3e5802ab028ee5cd8

with qw/
  Moo::Role::UserAgent
  Moo::Role::FileSystem
  Moo::Role::FileIO
  Moo::Role::UUID
  /;
ACCESSORS: {
	OPERATION: {
		has mute => ( is => 'rw' );
	}
	AUTH: {
		has user => ( is => 'rw', );
		has pass => ( is => 'rw', );
	}
	AUDIT: {
		has auditroot => ( is => 'rw' );
		has auditdir  => (
			is   => 'ro', # this should never change after creation surely? :thinkingface:
			lazy => 1,

			#straight copy Toolbox::FileSystem::buildtmpdirpath... which lead to it being refactord :dappershark:
			default => sub {
				my ( $self ) = @_;
				my $path = $self->buildtimepath( $self->auditroot() );
				$self->mkpath( $path );
				return $path;
			}
		);
		has logfilepath => (
			is      => 'rw',
			lazy    => 1,
			default => sub {
				my ( $self ) = @_;
				return $self->auditdir() . '/activity.log';
			}
		);
		has logfilehandle => (
			is      => 'rw',
			lazy    => 1,
			default => sub {
				my ( $self ) = @_;
				open( my $fh, ">:encoding(UTF-8)", $self->logfilepath() ) or confess( "Failed to open logfile! : $!" );

				#Cargo Cultin'
				my $h = select( $fh );
				$| = 1;
				select( $h );
			}
		);
	}
}

=head1 CODE
=head2 PRIMARY
	The heavy lifting
=cut

sub log {
	my ( $self, $msg ) = @_;

	#not happy with this ;\
	my ( $s, $usec ) = gettimeofday();
	my $fh = $self->logfilehandle;
	if ( $self->mute() ) {
		print $fh "[$s\_$usec]$msg$/";
	} else {
		my $msg = "[$s\_$usec]$msg$/";
		print $fh $msg;
		print $msg;
	}
}

sub logquit {
	my ( $self, $msg ) = @_;
	$self->log( $msg );
	exit;
}

=head2 SECONDARY
	the refactored methods
=cut

sub snakeuuid {
	my ( $self ) = @_;
	my $uuid = substr( $self->getuuid(), undef, 29 );
	$uuid =~ s|-|_|g;
	return $uuid;
}

sub gettimeofday {
	require Time::HiRes;
	return Time::HiRes::gettimeofday();
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
