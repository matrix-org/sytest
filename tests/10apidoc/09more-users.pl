# How many more users do we want?
my $LOCAL_USERS = 3;

prepare "More local users",
   requires => [qw( register_new_user first_api_client user
                    can_register )],

   provides => [qw( more_users local_users )],

   do => sub {
      my ( $register_new_user, $http, $user ) = @_;

      Future->needs_all( map {
         my $uid = "09more-users-$_";

         $register_new_user->( $http, $uid );
      } 1 .. $LOCAL_USERS
      )->then( sub {
         my @users = @_;

         provide more_users => \@users;
         provide local_users => [ $user, @users ];

         Future->done();
      })
   };
