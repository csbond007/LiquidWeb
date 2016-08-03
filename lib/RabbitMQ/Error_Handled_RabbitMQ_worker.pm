
package Error_Handled_RabbitMQ_worker ;
use strict;
use warnings;

use AnyEvent::RabbitMQ;

use InfluxDB_Operations qw(write);
use AWS qw(put_S3);
use Config_Reader qw(getConfigValueByKey);
use Log_Initializer qw(get_Logger);

use base 'Exporter';

our @EXPORT_OK = qw(error_handled_worker);

sub error_handled_worker {

	my $condvar = AnyEvent->condvar;
	my $ar      = AnyEvent::RabbitMQ->new ;

        get_Logger()->info("Starting Worker ");

        $ar->load_xml_spec()->connect(
      				      host       => getConfigValueByKey("rabbitMQHost"),
				      port       => getConfigValueByKey("rabbitMQport"),
				      user       => getConfigValueByKey("rabbitMQuser"),
				      pass       => getConfigValueByKey("rabbitMQpass"),
				      vhost      => '/',
		
				      on_success      => sub { _on_connect_success( $condvar, $ar, @_ ) },
				      on_failure      => sub { _error( $condvar, $ar, 'failure', @_ ) },
				      on_read_failure => sub { _error( $condvar, $ar, 'read_failure', @_ ) },
				      on_return       => sub { _error( $condvar, $ar, 'return', @_ ) },
				      on_close        => sub { _error( $condvar, $ar, 'close', @_ ) },
				     ) ; # end connect
  	$condvar->recv;

	return ;
			}  # error_handled_worker

############################################################################
sub _on_connect_success {

	my ( $condvar, $ar, $new_ar ) = @_;
	get_Logger()->info("Connected to RabbitMQ. ");
	_open_channel( $condvar, $new_ar );
  	return;
			} # end _on_connect_success

############################################################################
sub _open_channel {

	my ( $condvar, $ar ) = @_;
	get_Logger()->info("Opening RabbitMQ channel... ");
  	$ar->open_channel(
    			  on_success      => sub { _on_open_channel_success( $condvar, $ar, @_ ) },
		          on_failure      => sub { _error( $condvar, $ar, 'failure',      @_ ) },
		          on_read_failure => sub { _error( $condvar, $ar, 'read_failure', @_ ) },
		          on_return       => sub { _error( $condvar, $ar, 'return',       @_ ) },
		          on_close        => sub { _error( $condvar, $ar, 'close',        @_ ) },
  			 );  # end channel
  	return;
		}  # end _open_channel

############################################################################
sub _on_open_channel_success {
  
	my ( $condvar, $ar, $channel ) = @_;
	get_Logger()->info("Opened RabbitMQ channel. ");
        $channel->confirm;
	_declare_exchange( $condvar, $ar, $channel );
  	return;
			     }  # end _on_open_channel_success

############################################################################
sub _declare_exchange {

	my ( $condvar, $ar, $channel ) = @_;
	get_Logger()->info("Declaring RabbitMQ exchange... ");
  	$channel->declare_exchange(
				   exchange        => 'testest',
			           type            => 'fanout',

			           on_success      => sub { _on_declare_exchange_success( $condvar, $ar, $channel, @_ ) },
			           on_failure      => sub { _error( $condvar, $ar, 'failure',      @_ ) },
			           on_read_failure => sub { _error( $condvar, $ar, 'read_failure', @_ ) },
    				   on_return       => sub { _error( $condvar, $ar, 'return',       @_ ) },
    				   on_close        => sub { _error( $condvar, $ar, 'close',        @_ ) },
  				  );
  	return;
		      } # end _declare_exchange

############################################################################
sub _on_declare_exchange_success {

	my ( $condvar, $ar, $channel ) = @_;
	get_Logger()->info("Declared RabbitMQ exchange. ");
	_bind_exchange( $condvar, $ar, $channel );
  	return;
				} # end _on_declare_exchange_success

############################################################################
sub _bind_exchange {

	my ( $condvar, $ar, $channel ) = @_;
	get_Logger()->info("Binding RabbitMQ exchange... ");
	$channel->bind_exchange(
			        source      => 'testest',
    			        destination => 'testest',
    				routing_key => '',

			        on_success      => sub { _on_bind_exchange_success( $condvar, $ar, $channel, @_ ) },
    				on_failure      => sub { _error( $condvar, $ar, 'failure',      @_ ) },
			        on_read_failure => sub { _error( $condvar, $ar, 'read_failure', @_ ) },
			        on_return       => sub { _error( $condvar, $ar, 'return',       @_ ) },
			        on_close        => sub { _error( $condvar, $ar, 'close',        @_ ) },
  			       );
  	return;
		} # end _bind_exchange

############################################################################
sub _on_bind_exchange_success {

	my ( $condvar, $ar, $channel ) = @_;
	get_Logger()->info("Binded RabbitMQ exchange. ");
	_declare_queue( $condvar, $ar, $channel );
  	return;
			      } # end _on_bind_exchange_success

############################################################################
sub _declare_queue {
  
	my ( $condvar, $ar, $channel ) = @_;
	get_Logger()->info("Declaring RabbitMQ queue... ");

	$channel->declare_queue(
    				queue       => getConfigValueByKey("rabbitMQName_worker"),
			   #    auto_delete => 1,
			   #    passive     => 0,
    				durable     => 1,
			   #    exclusive   => 0,
			   #    no_ack      => 1,
			   #    ticket      => 0,
    
				on_success      => sub { _on_declare_queue_success( $condvar, $ar, $channel, @_ ) },
			        on_failure      => sub { _error( $condvar, $ar, 'failure',      @_ ) },
    				on_read_failure => sub { _error( $condvar, $ar, 'read_failure', @_ ) },
			        on_return       => sub { _error( $condvar, $ar, 'return',       @_ ) },
    				on_close        => sub { _error( $condvar, $ar, 'close',        @_ ) },
  			       );
	  return;
		 } # end _declare_queue

############################################################################
sub _on_declare_queue_success {

	my ( $condvar, $ar, $channel ) = @_;
	get_Logger()->info("Declared RabbitMQ queue. ");

 	sub callback {
	              get_Logger()->info("Inside worker call-back ");

        	      my $var  = shift;
                      my $body = $var->{body}->{payload};
                      print " [x] Received $body \n";

                      print " [x] Done\n";
                      $channel->ack();
		     } # end callback


	$channel->qos(prefetch_count => 1,);

	$channel->consume(
    			  on_consume => \&callback,
        		  no_ack     => 0,
                	); # end consume
  	return;
			} # end _on_declare_queue_success

############################################################################
sub _error {

	my ( $condvar, $ar, $type, @error ) = @_;
	get_Logger()->info("Error $type @error ");
  	$condvar->send( $condvar, $ar, $type, @error );
  	return;
	
	   } # end error

###########################################################################
