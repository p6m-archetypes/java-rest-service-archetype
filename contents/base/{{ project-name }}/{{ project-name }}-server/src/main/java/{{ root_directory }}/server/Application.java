package {{ root_package }}.server;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
{% if has_persistence %}
import org.springframework.context.annotation.Import;

import {{ group_id }}.persistence.PersistenceConfig;
{% endif %}

@SpringBootApplication
{% if has_persistence %}
@Import(PersistenceConfig.class)
{% endif %}
public class Application {

    public static void main(String[] args) {
        SpringApplication.run(Application.class, args);
    }
}
