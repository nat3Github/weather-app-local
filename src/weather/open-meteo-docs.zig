// open meteo api docs:

// hourly String array: A list of weather variables which should be returned. Values can be comma separated, or multiple &hourly= parameter in the URL can be used.

// daily String array: A list of daily weather variable aggregations which should be returned. Values can be comma separated, or multiple &daily= parameter in the URL can be used. If daily weather variables are specified, parameter timezone is required.

// current String array: A list of weather variables to get current conditions.

// past_days Integer (0-92), >0: If past_days is set, yesterday or the day before yesterday data are also returned.

// forecast_days Integer (0-16): 7 Per default, only 7 days are returned. Up to 16 days of forecast are possible.

// forecast_hours, forecast_minutely_15, past_hours,past_minutely_15 Integer (>0): Similar to forecast_days, the number of timesteps of hourly and 15-minutely data can controlled. Instead of using the current day as a reference, the current hour or the current 15-minute time-step is used.

// start_date, end_date String (yyyy-mm-dd): The time interval to get weather data. A day must be specified as an ISO8601 date (e.g. 2022-06-30).

// start_hour, end_hour, start_minutely_15, end_minutely_15 String (yyyy-mm-ddThh:mm): The time interval to get weather data for hourly or 15 minutely data. Time must be specified as an ISO8601 date (e.g. 2022-06-30T12:00).

// models String array auto: Manually select one or more weather models. Per default, the best suitable weather models will be combined.

// cell_selection String No land Set a preference how grid-cells are selected. The default land finds a suitable grid-cell on land with similar elevation to the requested coordinates using a 90-meter digital elevation model. sea prefers grid-cells on sea. nearest selects the nearest possible grid-cell.

// apikey String No: Only required to commercial use to access reserved API resources for customers. The server URL requires the prefix customer-. See pricing for more information.
