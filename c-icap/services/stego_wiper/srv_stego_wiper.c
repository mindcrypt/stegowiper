/*
 * stegowiper C-ICAP Service
 * Copyright (C) 2022 Manuel Urueña <muruenya@gmail.com>
 *
 * Portions of stegowiper C-ICAP Service contain code derived from, 
 * or inspired by C-ICAP echo service (http://c-icap.sourceforge.net/)
 * under the GNU General Public License (GPL) version 2 or later:
 * 
 * Copyright (C) 2004-2008 Christos Tsantilas
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
 * MA  02110-1301  USA.
 */

#include "common.h"
#include "c-icap.h"
#include "service.h"
#include "header.h"
#include "body.h"
#include "simple_api.h"
#include "debug.h"

#include <stdlib.h>
#include <errno.h>


int stegowiper_init_service(ci_service_xdata_t * srv_xdata,
                      struct ci_server_conf *server_conf);
int stegowiper_check_preview_handler(char *preview_data, int preview_data_len,
                               ci_request_t *);
int stegowiper_end_of_data_handler(ci_request_t * req);
void *stegowiper_init_request_data(ci_request_t * req);
void stegowiper_close_service();
void stegowiper_release_request_data(void *data);
int stegowiper_io(char *wbuf, int *wlen, char *rbuf, int *rlen, int iseof,
            ci_request_t * req);


CI_DECLARE_MOD_DATA ci_service_module_t service = {
    "stegoWiper",                 /* mod_name, The module name */
    "stegoWiper v0.1 service",    /* mod_short_descr,  Module short description */
    ICAP_RESPMOD | ICAP_REQMOD,     /* mod_type, The service type is responce or request modification */
    stegowiper_init_service,      /* mod_init_service. Service initialization */
    NULL,                           /* post_init_service. Service initialization after c-icap
                                       configured. Not used here */
    stegowiper_close_service,     /* mod_close_service. Called when service shutdowns. */
    stegowiper_init_request_data,     /* mod_init_request_data */
    stegowiper_release_request_data,  /* mod_release_request_data */
    stegowiper_check_preview_handler, /* mod_check_preview_handler */
    stegowiper_end_of_data_handler,   /* mod_end_of_data_handler */
    stegowiper_io,                    /* mod_service_io */
    NULL,
    NULL
};

/*
  The stegowiper_req_data structure will store the data required to serve an ICAP request.
*/
struct stegowiper_req_data {
  /*the body data*/
  //ci_ring_buf_t *body;
  ci_simple_file_t *file; 

  /*flag for marking the eof*/
  int eof;
};

/* This function will be called when the service loaded  */
int stegowiper_init_service(ci_service_xdata_t * srv_xdata,
			      struct ci_server_conf *server_conf)
{
    ci_debug_printf(5, "Initialization of stegoWiper service......\n");

    /*Tell to the icap clients that we can support up to 1024 size of preview data*/
    //ci_service_set_preview(srv_xdata, 1024);
    ci_service_set_preview(srv_xdata, 1024);

    /*Tell to the icap clients that we support 204 responses*/
    ci_service_enable_204(srv_xdata);

    /*Tell to the icap clients to send preview data for all files*/
    ci_service_set_transfer_preview(srv_xdata, "*");

    /*Tell to the icap clients that we want the X-Authenticated-User and X-Authenticated-Groups headers
      which contains the username and the groups in which belongs.  */
    ci_service_set_xopts(srv_xdata,  CI_XAUTHENTICATEDUSER|CI_XAUTHENTICATEDGROUPS);

    return CI_OK;
}

/* This function will be called when the service shutdown */
void stegowiper_close_service()
{
    ci_debug_printf(5,"stegoWiper shutdown!\n");
    /*Nothing to do*/
}

/*This function will be executed when a new request for stegowiper service arrives. This function will
  initialize the required structures and data to serve the request.
 */
void *stegowiper_init_request_data(ci_request_t * req)
{
    struct stegowiper_req_data *stegowiper_data;
    
    /*Allocate memory for the stegowiper_data */
    stegowiper_data = malloc(sizeof(struct stegowiper_req_data));
    if (!stegowiper_data) {
      ci_debug_printf(1, "Memory allocation failed inside stegowiper_init_request_data()!\n");
      return NULL;
    }
    
    int req_type = ci_req_type(req);
    if (req_type == ICAP_REQMOD) {
      ci_headers_list_t * http_req_headers = ci_http_request_headers(req);
      const char * first_req_line = ci_headers_first_line(http_req_headers);
      ci_debug_printf(5,"stegowiper_init_request_data(ICAP_REQMOD, %s)\n", first_req_line);
    } else if (req_type == ICAP_RESPMOD) {
      ci_headers_list_t * http_req_headers = ci_http_request_headers(req);
      const char * first_req_line = ci_headers_first_line(http_req_headers);
      ci_headers_list_t * http_resp_headers = ci_http_response_headers(req);
      const char * first_resp_line = ci_headers_first_line(http_resp_headers);
      ci_debug_printf(5,"stegowiper_init_request_data(ICAP_RESPMOD, '%s', '%s')\n", first_req_line, first_resp_line);
    } else if (req_type == ICAP_OPTIONS) {
      ci_debug_printf(5,"stegowiper_init_request_data(ICAP_OPTIONS)\n");
    } else {
      ci_debug_printf(5,"stegowiper_init_request_data(%d)\n", req_type);
    }

    /*If the ICAP request encapsulates a HTTP objects which contains body data and not only headers, 
      then allocate a ci_simple_file_t object to store the body data. */
    if (ci_req_hasbody(req)) {
      stegowiper_data->file = ci_simple_file_named_new("/var/tmp/stegowiper/", NULL, 10*1024*1014); /* 10 MiB */
    } else {
      stegowiper_data->file = NULL;
    }

    stegowiper_data->eof = 0;
    
    /* Return to the c-icap server the allocated data*/
    return stegowiper_data;
}


/* This function will be executed after the request served to release allocated data */
void stegowiper_release_request_data(void *data)
{
    ci_debug_printf(5,"stegowiper_release_request_data()\n");

    /*The data points to the stegowiper_req_data struct we allocated in function stegowiper_init_service */
    struct stegowiper_req_data *stegowiper_data = (struct stegowiper_req_data *)data;

    /*if we had body data, release the related allocated data*/
    if ((stegowiper_data != NULL) && (stegowiper_data->file != NULL)) {
      //ci_simple_file_destroy(stegowiper_data->file);
      ci_simple_file_release(stegowiper_data->file);
    }

    free(stegowiper_data);
}


int stegowiper_check_preview_handler(char *preview_data, int preview_data_len,
				       ci_request_t * req)
{
    ci_off_t content_len;

    ci_debug_printf(5,"stegowiper_check_preview_handler(data_len=%d)\n", preview_data_len);


    /*Get the stegowiper_req_data we allocated using the stegowiper_init_service function*/
    struct stegowiper_req_data *stegowiper_data = ci_service_data(req);
    if (stegowiper_data == NULL) {
      return CI_ERROR;
    }

    /*If there are not body data in HTTP encapsulated object but only headers
      respond with Allow204 (no modification required) and terminate here the ICAP transaction */
    if (!ci_req_hasbody(req)) {
      return CI_MOD_ALLOW204;
    }

    /*If there are is a Content-Length header in encapsulated HTTP object, read it
     and display a debug message (used here only for debuging purposes)*/
    content_len = ci_http_content_length(req);
    ci_debug_printf(9, "We expect to read: Content-Length=%" PRINTF_OFF_T " bytes of body data\n",
                    (CAST_OFF_T) content_len);

    /* The HTTP message has a body, let's check what is it. First, check if its Content-Type starts with "image/" */
    const char * content_type = NULL;
    int req_type = ci_req_type(req);
    if (req_type == ICAP_REQMOD) {
      ci_headers_list_t * http_req_headers = ci_http_request_headers(req);
      content_type = ci_headers_value(http_req_headers,"Content-Type");
    } else if (req_type == ICAP_RESPMOD) {      
      ci_headers_list_t * http_resp_headers = ci_http_response_headers(req);
      content_type = ci_headers_value(http_resp_headers,"Content-Type");
    }

    if ((content_type != NULL) && (strncmp(content_type, "image/", 6) == 0)) {
      ci_debug_printf(5,"ContentType=\"%s\" is an image file, processing it.\n", content_type);

      if (preview_data_len) {
	stegowiper_data->eof = ci_req_hasalldata(req);
	ci_simple_file_write(stegowiper_data->file, preview_data, preview_data_len, stegowiper_data->eof);
      }

      return CI_MOD_CONTINUE;
      
    } else {
      ci_debug_printf(5,"ContentType=\"%s\" is not an image file, ignoring it.\n", content_type);

      if (preview_data_len) {
	


	stegowiper_data->eof = ci_req_hasalldata(req);
	ci_simple_file_write(stegowiper_data->file, preview_data, preview_data_len, stegowiper_data->eof);
	if (stegowiper_data->eof) {
	  ci_req_unlock_data(req);
	}
      }

      /*Nothing to do just return an allow204 (No modification) to terminate here
	the ICAP transaction */
      ci_debug_printf(8, "Allow 204...\n");      

      return CI_MOD_ALLOW204;
    }
}

/* This function will called if we returned CI_MOD_CONTINUE in stegowiper_check_preview_handler
 function, after we read all the data from the ICAP client*/
int stegowiper_end_of_data_handler(ci_request_t * req)
{
    ci_debug_printf(5,"stegowiper_end_of_data_handler()\n");

    struct stegowiper_req_data *stegowiper_data = ci_service_data(req);
    if (!stegowiper_data || !stegowiper_data->file) {
      return CI_ERROR;
    }

    char* input_file_path = strdupa(stegowiper_data->file->filename);
    ci_debug_printf(5,"input file path='%s'\n", input_file_path);

    long int input_length = stegowiper_data->file->endpos;
    
    /* Stop writting into the input file */
    ci_simple_file_release(stegowiper_data->file);


    int input_file_path_size = strlen(input_file_path);
    char* output_file_path = alloca(input_file_path_size + 5); // "_out\0"
    sprintf(output_file_path, "%s_out", input_file_path);
    ci_debug_printf(5,"output file path='%s'\n", output_file_path);
       
    char command[256];

    int req_type = ci_req_type(req);
    if (req_type == ICAP_REQMOD || req_type == ICAP_RESPMOD) {
      sprintf(command, "/usr/local/bin/stegowiper.sh -c stegoWiped %s %s", input_file_path, output_file_path);
    }
    
    int err = system(command);
    if (err == -1) {
      ci_debug_printf(3, "system(\"%s\") has failed with errno %d: %s\n", command, errno, strerror(errno));
    } else {
      ci_debug_printf(5,"system(\"%s\") has returned with value %d\n", command, err);
    }

    /* Now open the output filename */
    stegowiper_data->file = ci_simple_file_open(output_file_path);
    if (stegowiper_data->file == NULL) {
      ci_debug_printf(3, "ci_simple_file_open(\"%s\") has failed\n", output_file_path);
      return CI_ERROR;
    }

    long int output_length = stegowiper_data->file->endpos;
    ci_debug_printf(5, "ci_simple_file_open(\"%s\") = %ld bytes\n", output_file_path, output_length);

    if (input_length != output_length) {
      ci_http_response_remove_header(req, "Content-Length");
      char content_length_header[64];
      sprintf(content_length_header, "Content-Length: %ld", output_length);
      ci_http_response_add_header(req, content_length_header);
    }
    
    /*mark the eof*/
    stegowiper_data->eof = 1;
    
    /* send data back to client */
    ci_req_unlock_data(req);

    /*and return CI_MOD_DONE */
    return CI_MOD_DONE;
}

/* This function will called if we returned CI_MOD_CONTINUE in stegowiper_check_preview_handler
   function, when new data arrived from the ICAP client and when the ICAP client is
   ready to get data.
*/
int stegowiper_io(char *wbuf, int *wlen, char *rbuf, int *rlen, int iseof,
		    ci_request_t * req)
{
  ci_debug_printf(5,"stegowiper_io(wlen=%d, rlen=%d, iseof=%d)\n", (wlen?*wlen:0), (rlen?*rlen:0), iseof);

  int ret;
  struct stegowiper_req_data *stegowiper_data = ci_service_data(req);
  ret = CI_OK;
  
  /*write the data read from icap_client to the stegowiper_data->file*/
  if (rlen && rbuf && stegowiper_data->file) {
    //*rlen = ci_ring_buf_write(stegowiper_data->body, rbuf, *rlen);
    *rlen = ci_simple_file_write(stegowiper_data->file, rbuf, *rlen, iseof);
    if (*rlen < 0) {
      ret = CI_ERROR;
    }
  }

  /*read some data from the stegowiper_data->file and put them to the write buffer to be send
    to the ICAP client*/
  if (wbuf && wlen && stegowiper_data->file) {
    //*wlen = ci_ring_buf_read(stegowiper_data->body, wbuf, *wlen);
    *wlen = ci_simple_file_read(stegowiper_data->file, wbuf, *wlen);
  }
  if (*wlen==0 && stegowiper_data->eof==1) {
    *wlen = CI_EOF;
  }
  
  return ret;
}
