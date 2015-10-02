# How many more users do we want?
my $LOCAL_USERS = 3;

prepare "More local users",
   requires => [qw( first_api_client user )],

   provides => [qw( more_users local_users )],

   do => sub {
      my ( $http, $user ) = @_;

      Future->needs_all( map {
         my $uid = "09more-users-$_";

         matrix_register_user( $http, $uid );
      } 1 .. $LOCAL_USERS
      )->then( sub {
         my @users = @_;

         provide more_users => \@users;
         provide local_users => [ $user, @users ];

         Future->done();
      })
   };
