package com.example;

import com.google.gson.Gson;

public class App {
    public static void main(String[] args) {
        Gson gson = new Gson();
        String json = gson.toJson("Gradle proxy E2E test — build succeeded!");
        System.out.println("Gradle proxy E2E test — build succeeded!");
        System.out.println("  gson version: 2.10.1");
        System.out.println("  json output: " + json);
    }
}
