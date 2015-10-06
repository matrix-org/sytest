# How many more users do we want?
my $REMOTE_USERS = 2;

prepare "Remote users",
   requires => [qw( api_clients )],

   provides => [qw( remote_users )],

   do => sub {
      my ( $clients ) = @_;
      my $http = $clients->[1];

      Future->needs_all( map {
         my $uid = "19remote-users-$_";

         matrix_register_user( $http, $uid )
      } 1 .. $REMOTE_USERS
      )->then( sub {
         my @users = @_;

         provide remote_users => \@users;

         Future->done();
      });
   };

push our @EXPORT, qw( remote_user_preparer remote_users_preparer );

sub remote_user_preparer
{
   remote_users_preparer( 1 );
}

sub remote_users_preparer
{
   my ( $count ) = @_;

   preparer(
      requires => [qw( api_clients )],

      do => sub {
         my ( $clients ) = @_;
         my $http = $clients->[1];

         Future->needs_all( map {
            matrix_register_user( $http )
         } 1 .. $count )
      }
   );
}
