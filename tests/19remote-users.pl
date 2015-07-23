# How many more users do we want?
my $REMOTE_USERS = 2;

prepare "Remote users",
   requires => [qw( register_new_user v1_clients can_register )],

   provides => [qw( remote_users )],

   do => sub {
      my ( $register_new_user, $clients ) = @_;
      my $http = $clients->[1];

      Future->needs_all( map {
         my $uid = "19remote-users-$_";

         $register_new_user->( $http, $uid )
      } 1 .. $REMOTE_USERS
      )->then( sub {
         my @users = @_;

         provide remote_users => \@users;

         Future->done();
      });
   };
