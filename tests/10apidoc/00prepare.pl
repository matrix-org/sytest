our @EXPORT = qw( User is_User do_request_json_for new_User );

my @KEYS = qw(
   http user_id device_id password access_token eventstream_token
   sync_next_batch saved_events pending_get_events device_message_next_batch
);

# A handy little structure for other scripts to find in 'user' and 'more_users'
struct User => [ @KEYS ], predicate => 'is_User';

sub do_request_json_for
{
   my ( $user, %args ) = @_;
   is_User( $user ) or croak "Expected a User";

   my $user_id = $user->user_id;
   ( my $uri = delete $args{uri} ) =~ s/:user_id/$user_id/g;

   my %params = (
      access_token => $user->access_token,
      %{ delete $args{params} || {} },
   );

   $user->http->do_request_json(
      uri          => $uri,
      params       => \%params,
      request_user => $user->user_id,
      %args,
   );
}


sub new_User
{
   my ( %params ) = @_;

   my $user = User( delete @params{ @KEYS } );

   if ( %params ) {
      die "Unexpected parameter to new_User";
   }

   return $user;
}
