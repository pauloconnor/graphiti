listen 5001 # by default Unicorn listens on port 8080
worker_processes 2 # this should be >= nr_cpus
pid "/tmp/unicorn_graphiti.pid"
stderr_path "/tmp/unicorn_graphiti_err.log"
stdout_path "/tmp/unicorn_graphiti_out.log"
