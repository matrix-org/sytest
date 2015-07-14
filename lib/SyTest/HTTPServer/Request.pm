package SyTest::HTTPServer::Request;
use 5.014; # ${^GLOBAL_PHASE}
use base qw( Net::Async::HTTP::Server::Request );

# A somewhat-hackish way to give NaH:Server::Request objects a ->respond_json method

use JSON qw( encode_json );

use Carp;

sub DESTROY
{
   return if ${^GLOBAL_PHASE} eq "DESTRUCT";
   my $self = shift or return;
   return if $self->{__responded};
   carp "Destroying unresponded HTTP request to ${\$self->path}";
}

sub respond
{
   my $self = shift;
   $self->{__responded}++;
   $self->SUPER::respond( @_ );
}

sub respond_json
{
   my $self = shift;
   my ( $json ) = @_;

   my $response = HTTP::Response->new( 200 );
   $response->add_content( encode_json $json );
   $response->content_type( "application/json" );
   $response->content_length( length $response->content );

   $self->respond( $response );
}

1;
