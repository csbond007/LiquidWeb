#!/usr/bin/perl
use strict;
use warnings;

#use RabbitMQ_Send qw(send);
#use RabbitMQ_Receive qw(receive);
use RabbitMQ_worker qw(worker);

#send();
#receive();
worker();
