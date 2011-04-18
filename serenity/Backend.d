/**
 * Serenity Web Framework
 *
 * Backend.d: Specify the inferface backends must comply to
 *
 * Authors: Robert Clipsham <robert@octarineparrot.com>
 * Copyright: Copyright (c) 2011, Robert Clipsham <robert@octarineparrot.com> 
 * License: New BSD License, see COPYING
 */
 module serenity.Backend;

 interface Backend
 {
     int loop();
 }
