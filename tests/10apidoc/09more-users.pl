# How many more users do we want?
my $LOCAL_USERS = 2;

# A handy little structure for other scripts to find in 'more_users'
use Struct::Dumb 'readonly_struct';
readonly_struct User => [qw( user_id access_token )];

prepare "More local users",
   requires => [qw( first_http_client can_register )],

   do => sub {
      my ( $http ) = @_;

      Future->needs_all( map {
         my $uid = "09more-users-$_";

         $http->do_request_json(
            method => "POST",
            uri    => "/register",

            content => {
               type     => "m.login.password",
               user     => $uid,
               password => "an0th3r s3kr1t",
            },
         )->then( sub {
            my ( $body ) = @_;
            Future->done( User( $body->{user_id}, $body->{access_token} ) );
         });
      } 1 .. $LOCAL_USERS
      )->then( sub {
         my @users = @_;

         provide more_users => \@users;

         Future->done();
      })
   };
