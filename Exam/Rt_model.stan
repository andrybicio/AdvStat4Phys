//The data block is used to declare variables passed as input to the model
data {
  
  //number of observations
  int<lower=1> T;
  
  //vector with our observables
  int daily_infections[T];
  //- if cumulative_p_delay is always 1, 
  //  then we assume that everyone that shows symptoms is suddenly tested and reported positive,
  //  this implies there is no delay in the Rt and, at the end, we cannot have underreporting of cases
  //- Use cumulative_p_delay generated by data, this takes into account the possibility that for the latest
  //  data we can face some sort of underreporting
  vector[T] cumulative_p_delay;
  
  //Next parameters must be POSITIVE by definitions
  //init parameters, step_size_prior_sd is the average the gaussian random walk step for Rt
  real<lower=0> step_size_prior_sd;
  real<lower=0> theta_init_mean;
  real<lower=0> theta_init_sd;
  
  //generation time parameters for Gamma distribution
  real<lower=0> shape_gt;
  real<lower=0> rate_gt;
}

// transformed data block is evaluated once, when model is compiled. 
transformed data {
  //vector containing the number of inferred infections that were likely to happen yesterday
  //later this vector, can be "normalized" to obtain the inferred number of infections
  vector[T-1] inferred_yesterday;
  
  for(t in 1:(T-1)) {
    inferred_yesterday[t] = daily_infections[t] / cumulative_p_delay[t];
  }
}

//The parameters block is used to declare stochastic variables of the model
parameters {
  real<lower=0> step_size;
  real theta_init;
  vector[T-2] theta_steps_unscaled;
  
  //this variable distributes according to the generation time
  real<lower=0> serial_interval;
}

//The transformed parameters and model blocks are evaluated and differentiated 
//at each leapfrog step, which is multiple times per iteration.
//Essentially, this implements the random walk for our Rt
transformed parameters {
  vector[T-1] theta = cumulative_sum(
    append_row(
      rep_vector(theta_init, 1),
      step_size * theta_steps_unscaled
    )
  );
}

model {
  //Gaussian RW for the theta (=> Rt) parameter
  step_size ~ normal(0, step_size_prior_sd);
  theta_init ~ normal(theta_init_mean, theta_init_sd);
  theta_steps_unscaled ~ normal(0, 1);
  
  //gamma distribution for serial interval:
  //i.e. time needed to generate a secondary infection
  serial_interval ~ gamma(
    shape_gt,
    rate_gt
  );
  
  //How many infections we would expect today it depends on:
  //- whether there is some sort of delay in reporting
  //- the number of people that were infected previous days
  //- the parameter theta, which drives the exponential
  {
    vector[T-1] expected_today = inferred_yesterday
      .* cumulative_p_delay[2:T]
      .* exp(theta);
    
    // Continuous approximation to Poisson as per Li/Dushoff/Bolker
    // The rt.live hack to make mean >= 0.1 MAKES A HUGE DIFFERENCE.
    for(t in 2:T) {
      daily_infections[t] ~ poisson(fmax(expected_today[t-1], 0.1));
    }
  }
}

//compute the Rt, which is untangled from the inference (indeed it depends only on theta)
generated quantities {
  vector[T-1] Rt = serial_interval * theta + 1.0;
}
