package {{ root_package }}.server.api;

import {{ group_id }}.persistence.{{ EntityName }}Entity;
import {{ group_id }}.persistence.{{ EntityName }}Repository;

import java.util.List;

import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

/**
 * The standard CRUD surface (p6m standards S2): a name-derived, versioned base path over the
 * {@code { id, displayName }} entity with conventional status semantics
 * (POST 201 / GET 200 / PUT 200 / DELETE 204 / 404 for unknown ids).
 */
@RestController
@RequestMapping("/api/v1/{{ entity-name }}s")
public class {{ EntityName }}Controller {

    public record {{ EntityName }}Request(String displayName) {
    }

    public record {{ EntityName }}Response(String id, String displayName) {
    }

    private final {{ EntityName }}Repository repository;

    public {{ EntityName }}Controller({{ EntityName }}Repository repository) {
        this.repository = repository;
    }

    private static {{ EntityName }}Response toResponse({{ EntityName }}Entity {{ entity_name }}) {
        return new {{ EntityName }}Response({{ entity_name }}.getId(), {{ entity_name }}.getDisplayName());
    }

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public {{ EntityName }}Response create(@RequestBody {{ EntityName }}Request request) {
        return toResponse(repository.save(new {{ EntityName }}Entity(request.displayName())));
    }

    @GetMapping
    public List<{{ EntityName }}Response> list() {
        return repository.findAll().stream().map({{ EntityName }}Controller::toResponse).toList();
    }

    @GetMapping("/{id}")
    public ResponseEntity<{{ EntityName }}Response> get(@PathVariable("id") String id) {
        return repository.findById(id)
                .map({{ entity_name }} -> ResponseEntity.ok(toResponse({{ entity_name }})))
                .orElseGet(() -> ResponseEntity.notFound().build());
    }

    @PutMapping("/{id}")
    public ResponseEntity<{{ EntityName }}Response> update(@PathVariable("id") String id, @RequestBody {{ EntityName }}Request request) {
        return repository.findById(id)
                .map({{ entity_name }} -> {
                    {{ entity_name }}.setDisplayName(request.displayName());
                    return ResponseEntity.ok(toResponse(repository.save({{ entity_name }})));
                })
                .orElseGet(() -> ResponseEntity.notFound().build());
    }

    @DeleteMapping("/{id}")
    public ResponseEntity<Void> delete(@PathVariable("id") String id) {
        if (!repository.existsById(id)) {
            return ResponseEntity.notFound().build();
        }
        repository.deleteById(id);
        return ResponseEntity.noContent().build();
    }
}
