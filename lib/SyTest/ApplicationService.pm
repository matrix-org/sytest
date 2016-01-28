package SyTest::ApplicationService;

use strict;
use warnings;

use Future::Utils qw( repeat );

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

sub info
{
   my $self = shift;
   return $self->{info};
}

sub await_http_request
{
   my $self = shift;
   my ( $path, @args ) = @_;

   $self->{await_http}->( $self->info->path . $path, @args );
}

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
