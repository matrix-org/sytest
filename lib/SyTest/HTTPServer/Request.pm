package SyTest::HTTPServer::Request;
use 5.014; # ${^GLOBAL_PHASE}
use base qw( Net::Async::HTTP::Server::Request );

use HTTP::Response;
use JSON qw( decode_json encode_json );

use constant JSON_MIME_TYPE => "application/json";

use SyTest::CarpByFile;

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

sub body_from_json
{
   my $self = shift;

   if( ( my $type = $self->header( "Content-Type" ) // "" ) ne JSON_MIME_TYPE ) {
      croak "Cannot ->body_from_json with Content-Type: $type";
   }

   return decode_json $self->body;
}

sub respond_json
{
   my $self = shift;
   my ( $json, %opts ) = @_;

   my $response = HTTP::Response->new( $opts{code} // 200 );
   $response->add_content( encode_json $json );
   $response->content_type( JSON_MIME_TYPE );
   $response->content_length( length $response->content );

   $self->respond( $response );
}

sub body_from_form
{
   my $self = shift;

   if( ( my $type = $self->header( "Content-Type" ) // "" ) ne "application/x-www-form-urlencoded" ) {
      croak "Cannot ->body_from_form with Content-Type: $type";
   }

   # TODO: Surely there's a neater way than this??
   return { URI->new( "http://?" . $self->body )->query_form };
}

1;
