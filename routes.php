<?php

return [
    ['POST', '/login', ['Repositories\AuthRepository', 'login']],
    ['POST', '/user/register', ['Repositories\UserRepository', 'register']],
    ['GET', '/user/get/{id}', ['Repositories\UserRepository', 'getById']],
    ['GET', '/user/search', ['Repositories\UserRepository', 'search']],
];