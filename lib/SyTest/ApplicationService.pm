package SyTest::ApplicationService;

use strict;
use warnings;

use Future::Utils qw( repeat );

=head1 NAME

C<SyTest::ApplicationService> - abstraction of a single application service

=head1 DESCRIPTION

An instance of this class represents an abstracted application service for the
homeserver to talk to. It provides the test scripts a way to receive inbound
HTTP requests and respond to them, and allows access to the user information
allowing a test script to send API requests.

=cut

=head1 CONSTRUCTOR

=cut

=head2 new

   $appserv = SyTest::ApplicationService->new( $info, $await_http )

Returns a newly constructed instance that uses the given C<ASInfo> structure
and the C<await_http> function.

=cut

sub new
{
   my $class = shift;
   my ( $info, $await_http ) = @_;

   my $path = $info->path;

   # Map event types to ARRAYs of Futures
   my %futures_by_type;

   my $f = repeat {
      $await_http->( qr{^\Q$path\E/transactions/\d+$}, sub { 1 },
         timeout => 0,
      )->then( sub {
         my ( $request ) = @_;

         # Respond immediately to AS
         $request->respond_json( {} );

         foreach my $event ( @{ $request->body_from_json->{events} } ) {
            my $type = $event->{type};

            my $queue = $futures_by_type{$type};

            # Ignore any cancelled ones
            shift @$queue while $queue and @$queue and $queue->[0]->is_cancelled;

            if( $queue and my $f = shift @$queue ) {
               $f->done( $event, $request );
            }
            else {
               warn "Ignoring incoming AS event of type $type\n";
            }
         }

         Future->done;
      })
   } while => sub { not $_[0]->failure };

   $f->on_fail( sub { die $_[0] } );

   return bless {
      info       => $info,
      await_http => $await_http,

      futures_by_type => \%futures_by_type,
      await_loop_f    => $f,
   }, $class;
}

=head1 METHODS

=cut

=head2 info

   $info = $appserv->info

Returns the C<ASInfo> structure instance this object was constructed with.

=cut

sub info
{
   my $self = shift;
   return $self->{info};
}

=head2 await_http_request

   $f = $appserv->await_http_request( $path, @args )

A wrapper around the C<await_http_request> function the instance was
constructed with, that prepends this server's path prefix onto the C<$path>
argument for convenience.

=cut

sub await_http_request
{
   my $self = shift;
   my ( $path, @args ) = @_;

   $self->{await_http}->( $self->info->path . $path, @args );
}

=head2 await_event

   $f = $appserv->await_event( $type )

Returns a L<Future> that will succeed with the next event of the given
C<$type> that the homeserver pushes to the application service.

=cut

sub await_event
{
   my $self = shift;
   my ( $type ) = @_;

   my $failmsg = SyTest::CarpByFile::shortmess(
      "Timed out waiting for an AS event of type $type"
   );

   push @{ $self->{futures_by_type}{$type} }, my $f = Future->new;

   return Future->wait_any(
      $f,

      main::delay( 10 )
         ->then_fail( $failmsg ),
   );
}

1;
